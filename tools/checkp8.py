# -*- coding: utf-8 -*-
"""Is this .p8 actually the key Apple thinks it gave you.

    python tools/checkp8.py ~/Downloads/AuthKey_ABCDE12345.p8

An APNs or DeviceCheck key is a PKCS#8 EC private key on the P-256 curve, and
everything downstream assumes exactly that: `supabase/functions/push/index.ts`
strips the PEM armour, base64-decodes it and hands the bytes to
`crypto.subtle.importKey` as `{name: "ECDSA", namedCurve: "P-256"}`. If any of
that is wrong the failure surfaces as a push that silently never arrives, hours
later, with nothing in the log pointing at the key.

So this checks it up front, **without sending the key anywhere and without
printing any of it.** No dependencies -- it reads the DER structure directly,
because requiring `pip install cryptography` to check a file is how a check stops
being run.

What it cannot tell you: whether the Key ID matches the key, or whether the key
is still valid at Apple. Only Apple knows those. It tells you the file is the
right *kind* of thing, which is the failure people actually hit -- a truncated
copy-paste, a downloaded HTML error page, or the wrong file entirely.
"""
import base64
import os
import re
import sys

# The two object identifiers that have to be in there, as DER bytes.
EC_PUBLIC_KEY = bytes.fromhex("2a8648ce3d0201")      # 1.2.840.10045.2.1
PRIME256V1 = bytes.fromhex("2a8648ce3d030107")       # 1.2.840.10045.3.1.7

# Other curves, so a wrong-but-plausible key is named rather than just refused.
OTHER_CURVES = {
    bytes.fromhex("2b81040022"): "P-384 (secp384r1)",
    bytes.fromhex("2b81040023"): "P-521 (secp521r1)",
    bytes.fromhex("2b8104000a"): "secp256k1",
}
RSA = bytes.fromhex("2a864886f70d010101")            # 1.2.840.113549.1.1.1


def check(path):
    problems = []
    notes = []

    if not os.path.exists(path):
        return ["There is no file at %s" % path], []

    with open(path, "rb") as handle:
        raw = handle.read()

    notes.append("%d bytes on disk" % len(raw))

    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return ["Not text at all. A .p8 is a PEM file; this looks binary."], notes

    if "-----BEGIN PRIVATE KEY-----" not in text:
        if "<html" in text.lower() or "<!doctype" in text.lower():
            problems.append(
                "This is an HTML page, not a key -- a download that failed and "
                "saved the error page instead."
            )
        else:
            problems.append(
                "No '-----BEGIN PRIVATE KEY-----' line. Apple's keys are PKCS#8; "
                "if yours says 'BEGIN EC PRIVATE KEY' it is the older SEC1 form "
                "and will not import."
            )
        return problems, notes

    if "-----END PRIVATE KEY-----" not in text:
        problems.append("The END line is missing -- the file is truncated.")

    body = re.sub(r"-----[A-Z ]+-----", "", text)
    body = re.sub(r"\s+", "", body)
    try:
        der = base64.b64decode(body, validate=True)
    except Exception as error:
        problems.append("The base64 between the armour lines will not decode (%s)."
                        % error)
        return problems, notes

    notes.append("%d bytes of DER once decoded" % len(der))

    if RSA in der:
        problems.append("This is an RSA key. Apple's APNs and DeviceCheck keys are "
                        "elliptic-curve, so this is the wrong key entirely.")
        return problems, notes

    if EC_PUBLIC_KEY not in der:
        problems.append("No ecPublicKey identifier in the structure -- this is not "
                        "an EC key.")

    if PRIME256V1 in der:
        notes.append("curve P-256 (prime256v1), which is what Apple issues")
    else:
        named = [name for oid, name in OTHER_CURVES.items() if oid in der]
        problems.append(
            "Not on P-256. Found %s." % (named[0] if named else "no curve I recognise")
        )

    # An Apple P-256 PKCS#8 key is 138 bytes of DER, give or take the optional
    # public-key component. Well outside that range means something is wrong even
    # if the identifiers happen to appear.
    if not (100 <= len(der) <= 200):
        problems.append("The DER is %d bytes; an Apple EC key is around 138. "
                        "Likely truncated or padded." % len(der))

    name = os.path.basename(path)
    match = re.match(r"AuthKey_([A-Z0-9]{10})\.p8$", name)
    if match:
        notes.append("Key ID from the filename: %s" % match.group(1))
    else:
        notes.append("Filename is not AuthKey_XXXXXXXXXX.p8, so the Key ID is not "
                     "in it -- make sure you have it written down separately")
    return problems, notes


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: checkp8.py <AuthKey_XXXXXXXXXX.p8> [more...]")

    bad = 0
    for path in sys.argv[1:]:
        print(os.path.basename(path))
        problems, notes = check(path)
        for note in notes:
            print("    %s" % note)
        if problems:
            bad += 1
            print()
            for problem in problems:
                print("    PROBLEM: %s" % problem)
        else:
            print("    Looks like a valid Apple EC key.")
        print()

    if bad:
        print("%d of %d file(s) will not work." % (bad, len(sys.argv) - 1))
    else:
        print("Both the key and its armour are the shape the push function expects.")
        print("Whether Apple still accepts it is a question only Apple can answer.")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
