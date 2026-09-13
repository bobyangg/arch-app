// Turn a signed-in Apple identity into an Arch account.
//
// By the time this runs, Supabase Auth has already verified Apple's identity token
// against Apple's own keys, so who the caller is, is settled. This adds the two
// things Supabase does not do:
//
//   1. **Attestation.** Proof the request came from an unmodified build of this app
//      on real Apple hardware, rather than from a script with a stolen token.
//   2. **The ban check.** Whether this device has been removed before, which is the
//      only part of the exchange that survives deleting the app.
//
// It is also the one place `accounts.apple_email` and `apple_name` can be captured.
// Apple sends those on the *first* authorization only; if they are not persisted
// here they are gone for good, and that is the single most common way this
// integration is got wrong.

import {
  admin, appId, caller, corsHeaders, isEnforced, json, refuse,
} from "../_shared/http.ts";
import { AttestError, base64ToBytes, verifyAttestation } from "../_shared/appattest.ts";
import { isConfigured, readBits, writeBits } from "../_shared/devicecheck.ts";

interface Body {
  challenge?: string;
  keyId?: string;
  attestation?: string;
  deviceToken?: string;
  name?: string;
  email?: string;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") return refuse(405, "method not allowed");

  const user = await caller(request);
  if (!user) return refuse(401, "sign in first");

  let body: Body;
  try {
    body = await request.json();
  } catch {
    return refuse(400, "bad request");
  }

  const db = admin();

  // ---------------------------------------------------------------- attestation
  //
  // The challenge must be one this server issued, to this user, and never spent.
  // All three, or a captured exchange is replayable.
  let attested = false;
  let attestFailure: string | null = null;
  let publicKey: Uint8Array | null = null;

  if (body.challenge && body.keyId && body.attestation) {
    const { data: row } = await db
      .from("attest_challenges")
      .select("challenge, account_id, used_at, created_at")
      .eq("challenge", body.challenge)
      .maybeSingle();

    const age = row ? Date.now() - new Date(row.created_at).getTime() : Infinity;
    if (!row || row.account_id !== user.id || row.used_at || age > 5 * 60 * 1000) {
      attestFailure = "challenge is not valid";
    } else {
      try {
        const result = await verifyAttestation(
          base64ToBytes(body.attestation),
          body.keyId,
          base64ToBytes(body.challenge),
          appId(),
        );
        // A development attestation against a production project means somebody
        // has pointed a debug build at live data.
        if (result.development && isEnforced()) {
          attestFailure = "development attestation refused";
        } else {
          attested = true;
          publicKey = result.publicKey;
        }
      } catch (error) {
        attestFailure = error instanceof AttestError ? error.message : "attestation failed";
      }
      // Spent either way. A challenge that survives a failed attempt is a
      // challenge somebody can keep guessing against.
      await db.from("attest_challenges")
        .update({ used_at: new Date().toISOString() })
        .eq("challenge", body.challenge);
    }
  } else {
    attestFailure = "no attestation supplied";
  }

  if (attestFailure) {
    console.warn("attestation not accepted", { user: user.id, reason: attestFailure });
    if (isEnforced()) return refuse(403, "this device could not be verified");
  }

  // ------------------------------------------------------------------ the ban
  //
  // Read before the account is created, so a banned device never gets one.
  //
  // When DeviceCheck is not configured the signup proceeds without it. That is the
  // right default for a project that does not have Apple credentials yet — the
  // alternative is nobody being able to sign up at all — but it does mean bans are
  // unenforceable until the keys are set. The log line is there to make that
  // visible rather than quietly true.
  let deviceSeenBefore = false;
  if (body.deviceToken && isConfigured()) {
    try {
      const bits = await readBits(body.deviceToken);
      if (bits.bit1) {
        console.warn("banned device attempted signup", { user: user.id });
        return json({
          status: "removed",
          reason: "device",
        }, 403);
      }
      deviceSeenBefore = bits.bit0;
    } catch (error) {
      // Apple being unreachable must not stop people joining. It is a soft signal
      // and the account can be reviewed later.
      console.error("DeviceCheck query failed", error);
    }
  } else if (body.deviceToken) {
    console.warn("DeviceCheck not configured; bans are not being enforced");
  }

  // --------------------------------------------------------------- the account
  //
  // Upsert, because signing back in after deleting the app runs this same path and
  // must land on the existing account rather than failing on the unique Apple id.
  const { data: existing } = await db
    .from("accounts")
    .select("id, status, apple_email, apple_name")
    .eq("id", user.id)
    .maybeSingle();

  if (existing?.status === "removed") {
    const { data: removal } = await db
      .from("removals")
      .select("kind, reason, until")
      .eq("account_id", user.id)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    return json({ status: "removed", reason: removal?.reason ?? "other",
                  kind: removal?.kind ?? "removed", until: removal?.until ?? null }, 403);
  }

  const { error: accountError } = await db.from("accounts").upsert({
    id: user.id,
    apple_user_id: user.id,
    // Only ever written, never overwritten with null: Apple sends these once, and
    // a later sign-in carrying nothing must not erase what the first one gave us.
    apple_email: existing?.apple_email ?? body.email ?? user.email ?? null,
    apple_name: existing?.apple_name ?? body.name ?? null,
    attested_at: attested ? new Date().toISOString() : existing ? undefined : null,
    device_seen_before: deviceSeenBefore,
  }, { onConflict: "id" });

  if (accountError) return refuse(500, "could not create the account", accountError);

  if (attested && publicKey && body.keyId) {
    const { error } = await db.from("account_devices").upsert({
      account_id: user.id,
      attest_key_id: body.keyId,
      attest_public_key: `\\x${[...publicKey].map((b) => b.toString(16).padStart(2, "0")).join("")}`,
      attest_counter: 0,
      last_seen: new Date().toISOString(),
    }, { onConflict: "attest_key_id" });
    if (error) console.error("could not record the device", error);
  }

  // Mark the device as having registered. bit1 is left alone — only moderation
  // sets that, and never this path.
  if (body.deviceToken && isConfigured()) {
    writeBits(body.deviceToken, { bit0: true, bit1: false })
      .catch((error) => console.error("DeviceCheck update failed", error));
  }

  // Whether onboarding is needed is a question about the profile, not the account:
  // somebody can have an account and have abandoned onboarding halfway.
  const { data: profile } = await db
    .from("profiles")
    .select("account_id")
    .eq("account_id", user.id)
    .maybeSingle();

  return json({
    status: "ok",
    isNewAccount: !existing,
    needsOnboarding: !profile,
    attested,
    // Told plainly, because the app decides whether to run the exchange again.
    attestationEnforced: isEnforced(),
  });
});
