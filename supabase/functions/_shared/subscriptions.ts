// Writing down what Apple said, against the right account.
//
// The only writer of `subscriptions`. The table has a read policy for its owner
// and nothing else, so no client can grant itself Premium -- and everything that
// reads Premium (seven slots in `match_population`, the location allowance, the
// notes on your profile) reads it from here.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type { SubscriptionFacts } from "./appstore.ts";

export type Recorded =
  | { kind: "recorded"; accountId: string; active: boolean; expiresAt: string }
  | { kind: "unclaimed" }
  | { kind: "refused"; reason: string };

/**
 * Attach a subscription to an account and store when it ends.
 *
 * **Whose it is** comes from Apple where Apple knows. The app passes the
 * account's id as `appAccountToken` when it buys, Apple keeps it on every
 * renewal, and that is authoritative: a phone cannot claim a purchase that
 * Apple says was made for somebody else, which is what stops one person's
 * subscription being restored onto another account by anyone who can read a
 * transaction id.
 *
 * Where Apple does not know -- an offer code redeemed outside the app carries no
 * token -- the account already holding the transaction keeps it, and failing
 * that the signed-in caller may claim it. A notification with neither has no
 * account to go to yet; the next time that person opens the app it is attached.
 *
 * @param claimant the signed-in caller, or null when Apple is the caller.
 */
export async function record(
  db: SupabaseClient,
  facts: SubscriptionFacts,
  claimant: string | null,
): Promise<Recorded> {
  const bundle = Deno.env.get("APP_BUNDLE_ID");
  if (facts.bundleId !== bundle) {
    return { kind: "refused", reason: "not a purchase in this app" };
  }

  const { data: holder } = await db
    .from("subscriptions")
    .select("account_id")
    .eq("apple_original_txn", facts.originalTransactionId)
    .maybeSingle();
  const heldBy: string | null = holder?.account_id ?? null;

  let account: string | null;
  if (facts.appAccountToken) {
    account = facts.appAccountToken;
    if (claimant && claimant !== account) {
      return { kind: "refused", reason: "this purchase belongs to another account" };
    }
  } else if (heldBy) {
    account = heldBy;
    if (claimant && claimant !== account) {
      return { kind: "refused", reason: "this purchase belongs to another account" };
    }
  } else {
    account = claimant;
  }
  if (!account) return { kind: "unclaimed" };

  // Apple's token outranks a row written earlier. The only way for the two to
  // disagree is a claim made before the token existed, and the token is the
  // record of who actually paid.
  if (heldBy && heldBy !== account) {
    await db.from("subscriptions").delete().eq("apple_original_txn", facts.originalTransactionId);
  }

  const expiresAt = facts.expiresAt.toISOString();
  const { error } = await db.from("subscriptions").upsert(
    {
      account_id: account,
      apple_original_txn: facts.originalTransactionId,
      expires_at: expiresAt,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "account_id" },
  );
  if (error) {
    // Most often an account that no longer exists: the token outlives a
    // deletion. Nothing to attach it to, and nothing a retry will change.
    console.error("could not record a subscription", error);
    return { kind: "refused", reason: "no such account" };
  }

  return { kind: "recorded", accountId: account, active: facts.expiresAt.getTime() > Date.now(), expiresAt };
}
