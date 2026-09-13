// The two bits Apple keeps for a device, across deleting the app.
//
// App Attest cannot recognise somebody coming back — its key is per-installation
// and dies with the app. This can: Apple stores two bits per device, for your team,
// and they survive reinstalling, signing out, and resetting the phone's data.
//
// How Arch spends them:
//
//   bit0 — this device has made an account before. A **soft** signal: flag for
//          review, rate-limit. Never a refusal. Households share iPads, people sell
//          phones, and somebody legitimately starting again is far more common than
//          somebody evading a ban. A hard block here buys little and generates false
//          positives forever.
//   bit1 — banned. A hard refusal at signup.
//
// Two bits is not much, and that is the point: it is enough to make coming back
// expensive without building a device fingerprint nobody consented to.
//
// The wall is the Apple ID, not this. A phone changes hands; an Apple ID mostly
// does not. This is corroboration.

const QUERY_URL = "https://api.devicecheck.apple.com/v1/query_two_bits";
const UPDATE_URL = "https://api.devicecheck.apple.com/v1/update_two_bits";

export interface DeviceBits {
  bit0: boolean;
  bit1: boolean;
  lastUpdated?: string;
}

/** Whether the credentials to talk to Apple are present at all. */
export const isConfigured = (): boolean =>
  Boolean(
    Deno.env.get("APPLE_TEAM_ID") &&
      Deno.env.get("APPLE_DEVICECHECK_KEY_ID") &&
      Deno.env.get("APPLE_DEVICECHECK_KEY"),
  );

/**
 * A short-lived ES256 token identifying this team to Apple.
 *
 * Signed with the DeviceCheck `.p8`, which is a server credential and must never
 * be anywhere near the app.
 */
async function appleToken(): Promise<string> {
  const teamId = Deno.env.get("APPLE_TEAM_ID")!;
  const keyId = Deno.env.get("APPLE_DEVICECHECK_KEY_ID")!;
  const pem = Deno.env.get("APPLE_DEVICECHECK_KEY")!;

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
  const encode = (value: unknown) =>
    btoa(JSON.stringify(value)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const head = encode({ alg: "ES256", kid: keyId, typ: "JWT" });
  const body = encode({ iss: teamId, iat: now, exp: now + 600 });

  const signature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      new TextEncoder().encode(`${head}.${body}`),
    ),
  );
  const signed = btoa(String.fromCharCode(...signature))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return `${head}.${body}.${signed}`;
}

/**
 * Read this device's bits.
 *
 * A device Apple has never been told about returns "not found", which is not an
 * error: it means this is the first account from this phone.
 */
export async function readBits(deviceToken: string): Promise<DeviceBits> {
  const response = await fetch(QUERY_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${await appleToken()}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      device_token: deviceToken,
      transaction_id: crypto.randomUUID(),
      timestamp: Date.now(),
    }),
  });

  const text = await response.text();
  if (response.status === 200) {
    const parsed = JSON.parse(text);
    return {
      bit0: Boolean(parsed.bit0),
      bit1: Boolean(parsed.bit1),
      lastUpdated: parsed.last_update_time,
    };
  }
  // Apple answers an unknown device with 200 and an empty body, or with this.
  if (/not found/i.test(text) || text.trim() === "") {
    return { bit0: false, bit1: false };
  }
  throw new Error(`DeviceCheck refused the query: ${response.status} ${text}`);
}

/** Write this device's bits. Called at signup, and when somebody is removed. */
export async function writeBits(
  deviceToken: string,
  bits: { bit0: boolean; bit1: boolean },
): Promise<void> {
  const response = await fetch(UPDATE_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${await appleToken()}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      device_token: deviceToken,
      transaction_id: crypto.randomUUID(),
      timestamp: Date.now(),
      bit0: bits.bit0,
      bit1: bits.bit1,
    }),
  });
  if (!response.ok) {
    throw new Error(`DeviceCheck refused the update: ${response.status}`);
  }
}
