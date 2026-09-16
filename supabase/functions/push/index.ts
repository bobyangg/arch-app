// Arch: delivering the one notification.
//
// Somebody wrote to you. A trigger on `messages` has already queued the row, with
// the sender's name and their words frozen into it, so this function's whole job
// is to hand what is waiting to Apple and record what happened.
//
// **An outbox drained on a schedule, not a call from the trigger.** A request made
// inside a trigger either rolls back the message when it fails or is lost without
// trace. A row committed alongside the message means a delivered message always
// has a queued notification, and a sweep that runs again in a minute is what makes
// the delivery eventually-correct rather than best-effort.
//
// Invoked by pg_cron over pg_net, so there is no user to authenticate. It is
// deployed with `verify_jwt` off and checks a shared secret instead -- a secret
// that authorises exactly this, rather than the service key, which would authorise
// everything.

import { admin, json, refuse } from "../_shared/http.ts";

const PRODUCTION = "https://api.push.apple.com";
const SANDBOX = "https://api.sandbox.push.apple.com";

/** How many to take per sweep. The sweep runs every minute; this is a valve. */
const BATCH = 100;

/** Give up on a row after this many tries and leave it for somebody to look at. */
const MAX_ATTEMPTS = 5;

// Apple asks that a provider token is not regenerated more than once every twenty
// minutes, and accepts one for an hour. Cached for the life of the isolate, which
// is a good deal shorter than either.
let cachedToken: { value: string; madeAt: number } | null = null;

function b64url(bytes: Uint8Array | string): string {
  const raw = typeof bytes === "string" ? bytes : String.fromCharCode(...bytes);
  return btoa(raw).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function providerToken(): Promise<string> {
  if (cachedToken && Date.now() - cachedToken.madeAt < 20 * 60 * 1000) {
    return cachedToken.value;
  }
  const teamId = Deno.env.get("APPLE_TEAM_ID")!;
  const keyId = Deno.env.get("APNS_KEY_ID")!;
  const pem = Deno.env.get("APNS_KEY")!;

  const der = Uint8Array.from(
    atob(pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "")),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const now = Math.floor(Date.now() / 1000);
  const head = b64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const body = b64url(JSON.stringify({ iss: teamId, iat: now }));
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      new TextEncoder().encode(head + "." + body),
    ),
  );
  const value = head + "." + body + "." + b64url(signature);
  cachedToken = { value, madeAt: Date.now() };
  return value;
}

interface Outbox {
  id: number;
  recipient_id: string;
  title: string;
  body: string;
  conversation_id: string;
  attempts: number;
}

interface DeviceToken {
  id: string;
  token: string;
  environment: string;
}

Deno.serve(async (request) => {
  // The secret authorises this one job. Using the service key here would hand the
  // whole database to anybody who found the URL.
  const expected = Deno.env.get("PUSH_CRON_SECRET");
  if (!expected || request.headers.get("x-arch-cron") !== expected) {
    return refuse(401, "not for you");
  }

  const configured = Deno.env.get("APPLE_TEAM_ID") && Deno.env.get("APNS_KEY_ID") &&
    Deno.env.get("APNS_KEY") && Deno.env.get("APP_BUNDLE_ID");
  if (!configured) {
    // Said out loud rather than passed over. Until the Apple keys exist the outbox
    // fills and nothing drains it, and that should be visible in a log rather than
    // discovered by somebody wondering why their phone is quiet.
    console.warn("APNs is not configured; the outbox is filling and not draining");
    return json({ status: "not configured", sent: 0 });
  }

  const db = admin();

  const { data: queued, error } = await db
    .from("push_outbox")
    .select("id, recipient_id, title, body, conversation_id, attempts")
    .is("sent_at", null)
    .lt("attempts", MAX_ATTEMPTS)
    .order("created_at", { ascending: true })
    .limit(BATCH);

  if (error) return refuse(500, "could not read the outbox", error);
  if (!queued?.length) {
    // An empty outbox used to return here, which meant the key was never touched
    // until there was something to send -- so a truncated paste or the wrong file
    // looked exactly like a working setup, and the first person to find out would
    // have been a real user whose message never arrived.
    //
    // **This branch is for a direct call, not for the sweep.** `private.sweep_push`
    // counts the outbox first and does not make the request at all when it is
    // empty, which is right -- a minute-by-minute job should not be a
    // minute-by-minute HTTP call. So this costs nothing in normal running and
    // exists so that a person, or `tools/checkpush.py`, can ask whether the key
    // Apple issued is the key that actually got pasted into the secret.
    try {
      await providerToken();
      return json({ status: "ok", sent: 0, key: "usable" });
    } catch (problem) {
      console.error("APNs key will not import", problem);
      return json({
        status: "ok",
        sent: 0,
        key: "unusable",
        why: String(problem),
      });
    }
  }

  const topic = Deno.env.get("APP_BUNDLE_ID")!;
  const jwt = await providerToken();

  let sent = 0;
  let dropped = 0;

  for (const row of queued as Outbox[]) {
    const { data: devices } = await db
      .from("push_tokens")
      .select("id, token, environment")
      .eq("account_id", row.recipient_id);

    if (!devices?.length) {
      // Notifications are on but this account has no device registered -- they
      // have never opened the app on a phone, or they declined at the system
      // prompt. Nothing to deliver to, and nothing to retry.
      await db.from("push_outbox")
        .update({ sent_at: new Date().toISOString(), last_error: "no device" })
        .eq("id", row.id);
      continue;
    }

    let delivered = false;
    let lastError: string | null = null;

    for (const device of devices as DeviceToken[]) {
      const host = device.environment === "sandbox" ? SANDBOX : PRODUCTION;
      try {
        const response = await fetch(`${host}/3/device/${device.token}`, {
          method: "POST",
          headers: {
            "authorization": `bearer ${jwt}`,
            "apns-topic": topic,
            "apns-push-type": "alert",
            // A person wrote to you. That is the only notification Arch sends, and
            // it is worth waking the screen for; there is nothing here that could
            // be batched to a quieter priority instead.
            "apns-priority": "10",
            // If it has not arrived within the day it is no longer news.
            "apns-expiration": String(Math.floor(Date.now() / 1000) + 86400),
            "apns-collapse-id": row.conversation_id.slice(0, 64),
            "content-type": "application/json",
          },
          body: JSON.stringify({
            aps: {
              alert: { title: row.title, body: row.body },
              sound: "default",
              // iOS groups by this, so several messages in one conversation
              // become one stack rather than seventeen banners. Apple's own
              // batching, so Arch does not have to invent a rule for it.
              "thread-id": row.conversation_id,
            },
            conversation: row.conversation_id,
          }),
        });

        if (response.ok) {
          delivered = true;
          continue;
        }

        const detail = await response.text();
        lastError = `${response.status} ${detail}`;

        // The phone no longer has the app, or the token was never valid. Keeping
        // it means failing against it forever.
        if (
          response.status === 410 ||
          /BadDeviceToken|Unregistered/i.test(detail)
        ) {
          await db.from("push_tokens").delete().eq("id", device.id);
          dropped += 1;
        } else {
          await db.from("push_tokens")
            .update({ last_failed_at: new Date().toISOString(), failure: lastError })
            .eq("id", device.id);
        }
      } catch (error) {
        lastError = String(error);
      }
    }

    if (delivered) {
      await db.from("push_outbox")
        .update({ sent_at: new Date().toISOString(), attempts: row.attempts + 1 })
        .eq("id", row.id);
      sent += 1;
    } else {
      // Left unsent so the next sweep tries again, up to MAX_ATTEMPTS. A message
      // that cannot be delivered is still delivered *in the app* -- the thread is
      // already there, and that is the part that matters.
      await db.from("push_outbox")
        .update({ attempts: row.attempts + 1, last_error: lastError })
        .eq("id", row.id);
    }
  }

  return json({ status: "ok", considered: queued.length, sent, dropped });
});
