// Arch: telling a person that somebody was reported.
//
// The Report sheet promises "a person will read it within a day". This is how a
// person finds out there is something to read: an email to the team, and a
// notification on every moderator's phone (`private.moderators`, backend/034).
//
// Invoked by `private.sweep_reports` over pg_net, every two minutes and only when
// a report is waiting, with the push job's shared secret -- the same arrangement
// as `push` and `photo-sweep`, and deployed with `verify_jwt` off for the same
// reason.
//
// **Email needs one thing set by hand:** `RESEND_API_KEY`, from resend.com, with
// archdating.com verified there so mail can come from it. Until it exists, the
// notification still goes and the email is retried on every sweep, up to thirty,
// so setting the key within the hour still delivers what was waiting.
//   REPORT_EMAIL_TO    defaults to support@archdating.com
//   REPORT_EMAIL_FROM  defaults to "Arch reports <reports@archdating.com>"
//
// **What the email does not carry is the conversation.** It names the report and
// how to read the conversation in the SQL Editor, so somebody's private messages
// are never copied into an inbox.

import { admin, json, refuse } from "../_shared/http.ts";

const PRODUCTION = "https://api.push.apple.com";
const SANDBOX = "https://api.sandbox.push.apple.com";
const DASHBOARD = "https://supabase.com/dashboard/project/bxuzpbzidrmoeietjnem";

/** What the sheet showed, for each code `removal_reason` takes. */
const REASONS: Record<string, string> = {
  abuse: "abusive or harassing",
  photos: "photos are not them",
  underage: "underage",
  selling: "trying to sell something",
  other: "something else",
};

// The provider token, as `push` makes it. Copied rather than shared so that
// changing one function can never break the other's delivery.
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

interface Person {
  id: string;
  name: string | null;
}

interface Report {
  id: string;
  reason: string;
  note: string | null;
  created_at: string;
  emailed: boolean;
  pushed: boolean;
  attempts: number;
  conversation_id: string | null;
  messages: number;
  also_blocked: boolean;
  reporter: Person;
  reported: Person & { status: string | null; reports_about_them: number };
}

interface Device {
  id: string;
  token: string;
  environment: string;
}

function emailFor(report: Report): { subject: string; text: string } {
  const reason = REASONS[report.reason] ?? report.reason;
  const reported = report.reported.name ?? "a deleted account";
  const reporter = report.reporter.name ?? "a deleted account";
  const lines = [
    `${reporter} reported ${reported}: ${reason}.`,
    "",
    `Note: ${report.note?.trim() || "(none)"}`,
    `Also blocked them: ${report.also_blocked ? "yes" : "no"}`,
    `Reports about ${reported} so far, this one included: ${report.reported.reports_about_them}`,
    `Their account status: ${report.reported.status ?? "unknown"}`,
    "",
    `Reported:  ${reported}  (${report.reported.id})`,
    `Reporter:  ${reporter}  (${report.reporter.id})`,
    `Filed:     ${report.created_at}`,
    `Report id: ${report.id}`,
    "",
  ];
  if (report.conversation_id) {
    lines.push(
      `The conversation (${report.messages} messages) is attached to the report. To read it, open the SQL Editor:`,
      `  ${DASHBOARD}/sql/new`,
      "and run:",
      `  select * from private.report_conversation('${report.id}');`,
    );
  } else {
    lines.push("No conversation is attached to this report.");
  }
  lines.push(
    "",
    "When it has been handled:",
    `  update reports set state = 'actioned', reviewed_at = now(), reviewer_note = '...' where id = '${report.id}';`,
    "(or state = 'dismissed' if nothing needed doing)",
    "",
    "The person reported is not told about the report.",
  );
  return {
    subject: `Arch report: ${reason} (${reported})`,
    text: lines.join("\n"),
  };
}

async function sendEmail(report: Report, key: string): Promise<string | null> {
  const { subject, text } = emailFor(report);
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "authorization": `Bearer ${key}`,
      "content-type": "application/json",
      // Resend sends a request with the same key once, so a sweep that runs
      // again before this one has recorded its result cannot email twice.
      "idempotency-key": `arch-report-${report.id}`,
    },
    body: JSON.stringify({
      from: Deno.env.get("REPORT_EMAIL_FROM") ?? "Arch reports <reports@archdating.com>",
      to: [Deno.env.get("REPORT_EMAIL_TO") ?? "support@archdating.com"],
      subject,
      text,
    }),
  });
  if (response.ok) return null;
  return `email ${response.status} ${await response.text()}`;
}

async function sendPush(report: Report, devices: Device[]): Promise<string | null> {
  const jwt = await providerToken();
  const topic = Deno.env.get("APP_BUNDLE_ID")!;
  let delivered = false;
  let lastError: string | null = null;
  for (const device of devices) {
    const host = device.environment === "sandbox" ? SANDBOX : PRODUCTION;
    try {
      const response = await fetch(`${host}/3/device/${device.token}`, {
        method: "POST",
        headers: {
          "authorization": `bearer ${jwt}`,
          "apns-topic": topic,
          "apns-push-type": "alert",
          "apns-priority": "10",
          "content-type": "application/json",
        },
        // No names on a lock screen. The email has the rest.
        body: JSON.stringify({
          aps: {
            alert: {
              title: "New report",
              body: `Someone was reported: ${REASONS[report.reason] ?? report.reason}. The details are in the support inbox.`,
            },
            sound: "default",
            "thread-id": "arch-reports",
          },
        }),
      });
      if (response.ok) {
        delivered = true;
      } else {
        lastError = `push ${response.status} ${await response.text()}`;
      }
    } catch (error) {
      lastError = `push ${String(error)}`;
    }
  }
  return delivered ? null : lastError;
}

Deno.serve(async (request) => {
  const expected = Deno.env.get("PUSH_CRON_SECRET");
  if (!expected || request.headers.get("x-arch-cron") !== expected) {
    return refuse(401, "not for you");
  }

  const db = admin();
  const { data, error } = await db.rpc("report_alerts_due", { _limit: 20 });
  if (error) return refuse(500, "could not read reports", error);

  const reports = (data?.reports ?? []) as Report[];
  const devices = (data?.devices ?? []) as Device[];
  const emailKey = Deno.env.get("RESEND_API_KEY");
  const pushReady = Boolean(
    devices.length && Deno.env.get("APPLE_TEAM_ID") && Deno.env.get("APNS_KEY_ID") &&
      Deno.env.get("APNS_KEY") && Deno.env.get("APP_BUNDLE_ID"),
  );

  let emailed = 0;
  let pushed = 0;

  for (const report of reports) {
    const changes: Record<string, unknown> = {};
    const problems: string[] = [];

    if (!report.pushed && pushReady) {
      const problem = await sendPush(report, devices);
      if (problem) problems.push(problem);
      else {
        changes.pushed_at = new Date().toISOString();
        pushed += 1;
      }
    }

    if (emailKey) {
      const problem = await sendEmail(report, emailKey);
      if (problem) problems.push(problem);
      else {
        changes.emailed_at = new Date().toISOString();
        emailed += 1;
      }
    } else {
      problems.push("RESEND_API_KEY is not set");
    }

    // Every pass that leaves the email unsent counts, so a missing key costs
    // thirty sweeps -- an hour -- and then stops asking.
    if (!changes.emailed_at) changes.alert_attempts = report.attempts + 1;
    changes.alert_error = problems.length ? problems.join("; ").slice(0, 1000) : null;

    await db.from("reports").update(changes).eq("id", report.id);
  }

  return json({
    status: "ok",
    considered: reports.length,
    emailed,
    pushed,
    email: emailKey ? "configured" : "RESEND_API_KEY not set",
    moderatorDevices: devices.length,
  });
});
