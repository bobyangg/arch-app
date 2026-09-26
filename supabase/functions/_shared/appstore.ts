// Asking Apple whether a subscription is live.
//
// **Apple is asked, not believed.** A phone can hand the server anything, and an
// App Store Server Notification arrives at a public URL that anybody can post
// to. Neither is trusted for what it says. Both are trusted for exactly one
// thing: *which* transaction to go and ask about. The answer comes from Apple's
// App Store Server API, over TLS, in reply to a request signed with this team's
// In-App Purchase key -- so the transport is what authenticates it, and there is
// no certificate chain to verify here and get subtly wrong.
//
// A forged notification can therefore do one thing: make this server re-check a
// real transaction, and write down whatever Apple says about it. That is the
// same thing a genuine one does.

const PRODUCTION = "https://api.storekit.itunes.apple.com";
const SANDBOX = "https://api.storekit-sandbox.itunes.apple.com";

/** Whether the In-App Purchase key is present. Without it, nothing can be confirmed. */
export const isConfigured = (): boolean =>
  Boolean(
    Deno.env.get("APPSTORE_ISSUER_ID") &&
      Deno.env.get("APPSTORE_KEY_ID") &&
      Deno.env.get("APPSTORE_KEY") &&
      Deno.env.get("APP_BUNDLE_ID"),
  );

const b64url = (bytes: Uint8Array): string =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

const encodeJSON = (value: unknown): string => b64url(new TextEncoder().encode(JSON.stringify(value)));

/**
 * A short-lived ES256 token for the App Store Server API.
 *
 * Signed with the In-App Purchase key from App Store Connect -- a different key
 * from the APNs one and the DeviceCheck one, and like them a server credential
 * that must never be anywhere near the app.
 */
async function apiToken(): Promise<string> {
  const pem = Deno.env.get("APPSTORE_KEY")!;
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
  const head = encodeJSON({ alg: "ES256", kid: Deno.env.get("APPSTORE_KEY_ID")!, typ: "JWT" });
  const body = encodeJSON({
    iss: Deno.env.get("APPSTORE_ISSUER_ID")!,
    iat: now,
    exp: now + 600,
    aud: "appstoreconnect-v1",
    bid: Deno.env.get("APP_BUNDLE_ID")!,
  });

  // WebCrypto answers ECDSA in IEEE P1363 form, r then s, which is exactly what
  // a JWS wants. The APNs sender relies on the same fact.
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${head}.${body}`)),
  );
  return `${head}.${body}.${b64url(signature)}`;
}

/**
 * The middle of a JWS, read without checking its signature.
 *
 * Only ever used on two kinds of input: what Apple's own API just returned to
 * an authenticated request, and a notification whose contents are used for
 * nothing but the transaction id to go and ask about.
 */
export function unverifiedPayload(jws: string): Record<string, unknown> | null {
  const middle = jws.split(".")[1];
  if (!middle) return null;
  try {
    const padded = middle.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((middle.length + 3) % 4);
    return JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(padded), (c) => c.charCodeAt(0))));
  } catch {
    return null;
  }
}

export interface SubscriptionFacts {
  originalTransactionId: string;
  productId: string;
  bundleId: string;
  /** The account the purchase was made for, if the app said so at purchase time. */
  appAccountToken: string | null;
  /** When it stops, allowing for a grace period and for a refund having ended it early. */
  expiresAt: Date;
  environment: "Production" | "Sandbox";
}

/**
 * What Apple says about a subscription, or null if Apple has never heard of it.
 *
 * Production first, then sandbox, which is Apple's own advice: TestFlight and
 * App Review both buy in the sandbox, and a transaction id carries no hint of
 * which environment it came from.
 */
export async function subscriptionFacts(originalTransactionId: string): Promise<SubscriptionFacts | null> {
  const token = await apiToken();
  for (const host of [PRODUCTION, SANDBOX]) {
    const response = await fetch(`${host}/inApps/v1/subscriptions/${encodeURIComponent(originalTransactionId)}`, {
      headers: { "Authorization": `Bearer ${token}` },
    });
    if (response.status === 404) continue;
    if (!response.ok) {
      throw new Error(`App Store Server API answered ${response.status}: ${await response.text()}`);
    }
    return read(await response.json(), originalTransactionId);
  }
  return null;
}

function read(answer: Record<string, unknown>, wanted: string): SubscriptionFacts | null {
  const groups = (answer.data as Array<{ lastTransactions?: unknown[] }> | undefined) ?? [];
  for (const group of groups) {
    for (const last of (group.lastTransactions ?? []) as Array<Record<string, unknown>>) {
      if (String(last.originalTransactionId) !== wanted) continue;

      const transaction = unverifiedPayload(String(last.signedTransactionInfo ?? ""));
      if (!transaction) continue;
      const renewal = unverifiedPayload(String(last.signedRenewalInfo ?? "")) ?? {};

      const expires = Number(transaction.expiresDate ?? 0);
      const revoked = transaction.revocationDate ? Number(transaction.revocationDate) : null;
      const grace = renewal.gracePeriodExpiresDate ? Number(renewal.gracePeriodExpiresDate) : 0;

      // Status 4 is Apple's billing grace period: the card failed, Apple is
      // retrying, and the subscriber keeps what they paid for while it does. A
      // refund is the opposite -- it ends the subscription at the moment of the
      // refund, whatever the expiry said.
      let until = expires;
      if (Number(last.status) === 4 && grace > until) until = grace;
      if (revoked !== null) until = Math.min(until, revoked);

      return {
        originalTransactionId: wanted,
        productId: String(transaction.productId ?? ""),
        bundleId: String(transaction.bundleId ?? ""),
        appAccountToken: transaction.appAccountToken ? String(transaction.appAccountToken).toLowerCase() : null,
        expiresAt: new Date(until),
        environment: String(answer.environment) === "Sandbox" ? "Sandbox" : "Production",
      };
    }
  }
  return null;
}
