// The bits both functions need: who is calling, how to answer, and a way to reach
// the database with the service key.

import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/**
 * What a caller is told when something goes wrong.
 *
 * Deliberately short and never specific. An attacker probing the attestation
 * exchange learns nothing from "attestation answers a different challenge" that
 * they should be told, and a person who has hit a genuine bug is not helped by it
 * either — the detail belongs in the log.
 */
export function refuse(status: number, reason: string, detail?: unknown): Response {
  if (detail) console.error(reason, detail);
  return json({ error: reason }, status);
}

/**
 * The admin client. Bypasses row-level security entirely.
 *
 * Every function here needs it, because the tables they write — `accounts`,
 * `account_devices`, `attest_challenges` — have no insert policy on purpose. A
 * client that could write its own account row could choose its own Apple id and
 * inherit somebody else's ban.
 */
export function admin(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

/**
 * The signed-in caller, or null.
 *
 * Sign-in with Apple has already happened by this point: Supabase Auth verified
 * Apple's identity token against Apple's own keys and issued this session. So the
 * user id here is trustworthy, and these functions never have to re-verify Apple.
 * What they add is everything Supabase does not do — attestation, and the ban
 * check.
 */
export async function caller(request: Request): Promise<{ id: string; email?: string } | null> {
  const header = request.headers.get("Authorization");
  if (!header?.startsWith("Bearer ")) return null;

  const client = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: header } }, auth: { persistSession: false } },
  );
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) return null;
  return { id: data.user.id, email: data.user.email ?? undefined };
}

/**
 * Whether a failed attestation should stop a signup.
 *
 * Off by default, and that is on purpose. Turning attestation on and enforcing it
 * in the same change means the first failure you see is indistinguishable from
 * every real user being locked out. Run it unenforced, watch
 * `accounts.attested_at` fill in, and set `ATTEST_ENFORCED=true` once the numbers
 * say the exchange works on real devices.
 *
 * It is also false on the simulator, which cannot attest at all.
 */
export const isEnforced = (): boolean =>
  Deno.env.get("ATTEST_ENFORCED")?.toLowerCase() === "true";

export const appId = (): string =>
  `${Deno.env.get("APPLE_TEAM_ID") ?? ""}.${Deno.env.get("APP_BUNDLE_ID") ?? ""}`;
