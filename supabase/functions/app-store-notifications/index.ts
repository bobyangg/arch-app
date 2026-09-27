// Apple, telling us a subscription changed.
//
// App Store Server Notifications V2 post here on every renewal, lapse, refund,
// billing retry and grace period. Set this function's URL as the Production and
// Sandbox server URL in App Store Connect -> App Information.
//
// **Deployed without JWT verification, because Apple has no Supabase session.**
// Which is why nothing in the body is believed: the notification is read only
// for the transaction id, and what gets recorded is what Apple's own API says
// about that transaction when asked directly. A forged post can make this server
// re-check a real subscription and write down the truth. That is all.
//
// Non-200 answers are deliberate where a retry would help. Apple retries a
// failed delivery several times over the following days, so "the key is not set
// yet" or "Apple's API did not answer" becomes a notification that arrives again
// later rather than one that is gone.

import { admin, json, refuse } from "../_shared/http.ts";
import { isConfigured, subscriptionFacts, unverifiedPayload } from "../_shared/appstore.ts";
import { record } from "../_shared/subscriptions.ts";

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ status: "ok" });

  if (!isConfigured()) {
    console.warn("App Store notification received but the In-App Purchase key is not set; asking Apple to retry");
    return refuse(503, "not configured");
  }

  let signedPayload = "";
  try {
    signedPayload = String((await request.json())?.signedPayload ?? "");
  } catch {
    return refuse(400, "bad request");
  }

  const notification = unverifiedPayload(signedPayload);
  const data = notification?.data as Record<string, unknown> | undefined;
  const transaction = data?.signedTransactionInfo
    ? unverifiedPayload(String(data.signedTransactionInfo))
    : null;
  const id = transaction?.originalTransactionId ? String(transaction.originalTransactionId) : "";

  // A TEST notification from App Store Connect, or one about something that is
  // not a transaction. Acknowledged, so Apple stops sending it.
  if (!/^\d{1,32}$/.test(id)) {
    console.log("App Store notification with no transaction", notification?.notificationType ?? "unknown");
    return json({ status: "ok" });
  }

  let facts;
  try {
    facts = await subscriptionFacts(id);
  } catch (problem) {
    return refuse(502, "could not reach Apple", problem);
  }
  if (!facts) return json({ status: "ok" });

  const outcome = await record(admin(), facts, null);
  console.log("App Store notification", notification?.notificationType ?? "unknown", outcome.kind);
  return json({ status: "ok" });
});
