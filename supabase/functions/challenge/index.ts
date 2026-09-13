// Issue a one-time challenge for App Attest.
//
// The device attests *over* a value this server chose and remembers. Without that
// step the whole exchange proves only that somebody, once, had a real iPhone — a
// captured attestation could be replayed for every fake account after it.
//
// Deliberately requires a session. Sign-in with Apple happens first, so a challenge
// is always tied to a known user, and an unauthenticated caller cannot farm them.

import { caller, corsHeaders, admin, json, refuse } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return refuse(405, "method not allowed");
  }

  const user = await caller(request);
  if (!user) return refuse(401, "sign in first");

  // 32 bytes from the platform CSPRNG. The client never chooses any part of it.
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  const challenge = btoa(String.fromCharCode(...bytes));

  const db = admin();
  const { error } = await db.from("attest_challenges").insert({
    challenge,
    account_id: user.id,
  });
  if (error) return refuse(500, "could not issue a challenge", error);

  // Cheap, and it keeps a table that gets one row per signup attempt from growing
  // without limit. Failing here must not fail the request.
  db.rpc("prune_attest_challenges").then(
    () => {},
    (error: unknown) => console.warn("prune failed", error),
  );

  return json({ challenge });
});
