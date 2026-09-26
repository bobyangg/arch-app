// The app bought something, or found something to restore: confirm it with
// Apple and record it.
//
// `POST /functions/v1/subscription` with `{ original_transaction_id }`, signed in.
// Answers `{ active, expires_at }` -- read back from Apple, never from the request.
//
// The app does not finish the StoreKit transaction until this answers. If it
// cannot be reached, the transaction stays open and StoreKit hands it back on the
// next launch, which is the retry: a purchase is never recorded on the phone and
// lost on the way to the server.

import { admin, caller, json, refuse } from "../_shared/http.ts";
import { isConfigured, subscriptionFacts } from "../_shared/appstore.ts";
import { record } from "../_shared/subscriptions.ts";

Deno.serve(async (request) => {
  const who = await caller(request);
  if (!who) return refuse(401, "not signed in");

  if (!isConfigured()) {
    // Said out loud, like the push sender does. Until the In-App Purchase key is
    // set, a real purchase cannot become Premium -- and the person who paid
    // should be the last to find that out, not the first.
    console.warn("App Store Server API is not configured; a purchase could not be confirmed");
    return refuse(503, "purchases are not set up yet");
  }

  let id = "";
  try {
    const body = await request.json();
    id = String(body?.original_transaction_id ?? "").trim();
  } catch {
    return refuse(400, "bad request");
  }
  // Apple's transaction ids are decimal strings. Anything else is not one, and
  // is not worth a round trip to Apple to find out.
  if (!/^\d{1,32}$/.test(id)) return refuse(400, "bad request");

  let facts;
  try {
    facts = await subscriptionFacts(id);
  } catch (problem) {
    return refuse(502, "could not reach Apple", problem);
  }
  if (!facts) return refuse(404, "Apple has no record of that purchase");

  const outcome = await record(admin(), facts, who.id);
  switch (outcome.kind) {
    case "refused":
      return refuse(403, outcome.reason);
    case "unclaimed":
      // Cannot happen with a signed-in caller, who is always a claimant. Here so
      // the switch is exhaustive rather than so it is reachable.
      return refuse(409, "no account to attach this to");
    case "recorded":
      return json({ active: outcome.active, expires_at: outcome.expiresAt });
  }
});
