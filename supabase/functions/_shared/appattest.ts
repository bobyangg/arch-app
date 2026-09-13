// Verifying that a request came from the real Arch, on a real Apple device.
//
// This is the piece `Arch/App/Attestation.swift` produces material for and cannot
// itself perform. The client generates a key, asks Apple to attest it, and sends
// the result here. **Every check that matters is in this file**, because a client
// deciding whether it is genuine is not a security control.
//
// What it proves: the request came from an unmodified build of *this* app, on
// genuine Apple hardware, with a key Apple vouched for. A signup farm cannot
// produce that without buying iPhones and running this binary.
//
// What it does not prove: that there is a real person behind it, or that this
// device has not been seen before — the key is per-installation and is gone when
// the app is deleted. Recognising somebody coming back is DeviceCheck's job.
//
// The steps below are Apple's, in Apple's order:
// https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server

import { decode as cborDecode } from "npm:cbor-x@1.5.9";
import * as x509 from "npm:@peculiar/x509@1.11.0";

/** Apple's extension carrying the nonce the device signed over. */
const NONCE_OID = "1.2.840.113635.100.8.2";

/**
 * Apple's App Attest root.
 *
 * **Fetched rather than pinned, and that is a compromise worth understanding.**
 * Pinning the PEM in source is what Apple recommends: it removes any dependency on
 * the network at verification time and on Apple's web server staying honest. It is
 * fetched here because a root certificate transcribed from memory would be worse
 * than either — subtly wrong, and failing in a way that looks like every device
 * being broken.
 *
 * Before this carries real traffic: download it once, paste it in below as a
 * constant, and delete the fetch.
 *
 *   curl -O https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem
 */
const ROOT_URL =
  "https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem";

let rootPromise: Promise<x509.X509Certificate> | null = null;

function appleRoot(): Promise<x509.X509Certificate> {
  // Cached for the life of the isolate, so this is once per cold start rather
  // than once per signup.
  rootPromise ??= (async () => {
    const response = await fetch(ROOT_URL);
    if (!response.ok) {
      throw new AttestError("could not load Apple's root certificate");
    }
    return new x509.X509Certificate(await response.text());
  })();
  return rootPromise;
}

export class AttestError extends Error {}

export interface Attested {
  /** The attested public key, for verifying later assertions. */
  publicKey: Uint8Array;
  /** Always zero for a fresh attestation; assertions increment it. */
  counter: number;
  /** True on a development build. Never accept one in production. */
  development: boolean;
}

const sha256 = async (data: Uint8Array): Promise<Uint8Array> =>
  new Uint8Array(await crypto.subtle.digest("SHA-256", data));

const concat = (...parts: Uint8Array[]): Uint8Array => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const part of parts) {
    out.set(part, at);
    at += part.length;
  }
  return out;
};

const same = (a: Uint8Array, b: Uint8Array): boolean =>
  a.length === b.length && a.every((byte, i) => byte === b[i]);

export const base64ToBytes = (value: string): Uint8Array =>
  Uint8Array.from(atob(value), (c) => c.charCodeAt(0));

/**
 * Verify an attestation.
 *
 * @param attestation the CBOR object from `DCAppAttestService.attestKey`
 * @param keyId       the key identifier the device reported, base64
 * @param challenge   the challenge this server issued, as raw bytes
 * @param appId       "TEAMID.bundle.identifier"
 */
export async function verifyAttestation(
  attestation: Uint8Array,
  keyId: string,
  challenge: Uint8Array,
  appId: string,
): Promise<Attested> {
  let decoded: { fmt?: string; attStmt?: { x5c?: Uint8Array[] }; authData?: Uint8Array };
  try {
    decoded = cborDecode(attestation);
  } catch {
    throw new AttestError("attestation is not valid CBOR");
  }

  if (decoded.fmt !== "apple-appattest") {
    throw new AttestError(`unexpected attestation format: ${decoded.fmt}`);
  }
  const chain = decoded.attStmt?.x5c;
  const authData = decoded.authData;
  if (!chain?.length || !authData) {
    throw new AttestError("attestation is missing its certificate chain");
  }

  // 1. The chain, up to Apple's root.
  const certs = chain.map((der) => new x509.X509Certificate(new Uint8Array(der)));
  const credCert = certs[0];
  const builder = new x509.X509ChainBuilder({ certificates: certs.slice(1) });
  const built = await builder.build(credCert);
  const root = await appleRoot();
  const anchored = built.some((cert) => cert.equal(root)) ||
    await built[built.length - 1].verify({ publicKey: await root.publicKey.export() })
      .then(() => true).catch(() => false);
  if (!anchored) {
    throw new AttestError("certificate chain does not reach Apple's root");
  }
  for (let i = 0; i < built.length - 1; i++) {
    const ok = await built[i].verify({ publicKey: await built[i + 1].publicKey.export() })
      .catch(() => false);
    if (!ok) throw new AttestError("certificate chain does not verify");
  }
  const now = new Date();
  if (credCert.notBefore > now || credCert.notAfter < now) {
    throw new AttestError("attestation certificate is not currently valid");
  }

  // 2. The nonce the device signed over is ours, and nobody else's.
  //
  // This is the replay defence. Everything else in the attestation would be just
  // as valid a second time; only this ties it to the challenge we issued a moment
  // ago and have not accepted before.
  const clientDataHash = await sha256(challenge);
  const expectedNonce = await sha256(concat(authData, clientDataHash));

  const extension = credCert.getExtension(NONCE_OID);
  if (!extension) throw new AttestError("attestation has no nonce extension");
  const nonce = extractNonce(new Uint8Array(extension.value));
  if (!nonce || !same(nonce, expectedNonce)) {
    throw new AttestError("attestation answers a different challenge");
  }

  // 3. The key identifier is the hash of the attested public key, so the client
  //    cannot claim a key it does not hold.
  const spki = new Uint8Array(await credCert.publicKey.rawData);
  const publicKey = uncompressedPoint(spki);
  const computedKeyId = await sha256(publicKey);
  if (!same(computedKeyId, base64ToBytes(keyId))) {
    throw new AttestError("key identifier does not match the attested key");
  }

  // 4. authData: this app, a fresh key, and a real environment.
  if (authData.length < 37) throw new AttestError("authenticator data is too short");
  const rpIdHash = authData.slice(0, 32);
  if (!same(rpIdHash, await sha256(new TextEncoder().encode(appId)))) {
    throw new AttestError("attestation is for a different app");
  }

  const counter = new DataView(
    authData.buffer, authData.byteOffset + 33, 4,
  ).getUint32(0);
  if (counter !== 0) {
    throw new AttestError("a fresh attestation must have a zero counter");
  }

  // aaguid says which environment produced it. A development attestation from a
  // production client means somebody is pointing a debug build at live data.
  const aaguid = new TextDecoder().decode(authData.slice(37, 53)).replace(/\0+$/, "");
  if (aaguid !== "appattest" && aaguid !== "appattestdevelop") {
    throw new AttestError(`unexpected attestation environment: ${aaguid}`);
  }

  // 5. The credential id inside authData is the key id again. Apple puts it in
  //    both places; if they disagree, something has been spliced together.
  const credentialIdLength = new DataView(
    authData.buffer, authData.byteOffset + 53, 2,
  ).getUint16(0);
  const credentialId = authData.slice(55, 55 + credentialIdLength);
  if (!same(credentialId, base64ToBytes(keyId))) {
    throw new AttestError("credential id does not match the key id");
  }

  return {
    publicKey,
    counter,
    development: aaguid === "appattestdevelop",
  };
}

/**
 * Pull the 32-byte nonce out of Apple's extension.
 *
 * The extension is a DER SEQUENCE holding a context-specific [1] wrapping an
 * OCTET STRING. Rather than write a DER parser for one field, this finds the
 * 32-byte OCTET STRING header (0x04 0x20) and takes what follows — and then the
 * caller compares it to a value we computed, so a wrong guess here fails closed.
 */
function extractNonce(value: Uint8Array): Uint8Array | null {
  for (let i = 0; i + 33 < value.length + 1; i++) {
    if (value[i] === 0x04 && value[i + 1] === 0x20 && i + 2 + 32 <= value.length) {
      return value.slice(i + 2, i + 34);
    }
  }
  return null;
}

/**
 * The raw P-256 point from a SubjectPublicKeyInfo.
 *
 * Apple hashes the uncompressed point — 0x04 followed by X and Y — not the whole
 * SPKI wrapper, so the last 65 bytes are what the key identifier is built from.
 */
function uncompressedPoint(spki: Uint8Array): Uint8Array {
  const point = spki.slice(spki.length - 65);
  if (point[0] !== 0x04) {
    throw new AttestError("attested key is not an uncompressed P-256 point");
  }
  return point;
}
