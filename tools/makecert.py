# -*- coding: utf-8 -*-
"""Make a distribution certificate, because nothing else will.

    python tools/makecert.py <output directory>

**Why this exists.** `-allowProvisioningUpdates` creates *development*
certificates and will not create a distribution one, so automatic signing fell
back to development and then asked for a registered device — on an account with
none, building an App Store archive, which needs no devices at all. The survey in
`ascheck.py` said so plainly: one DEVELOPMENT certificate, no profiles, no
devices.

The usual fix is a Mac: Keychain Access makes a signing request, you upload it,
you download a certificate. There is no Mac here. But the App Store Connect API
does the same three steps, so this does them.

**The private key lives for one run and is then thrown away.** A certificate is
useless without it, so a certificate left behind at Apple would be dead weight
counting against the limit of three. Every run therefore revokes the ones it made
before creating a new one, and the account stays at one.

Nothing is printed except paths and fingerprints. The key and the passphrase go to
files in the output directory, and the passphrase is random per run.
"""
import base64
import json
import os
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
AUDIENCE = "appstoreconnect-v1"
# The name this tool puts on its own certificates, so it can recognise and revoke
# them later without touching one a person made.
LABEL = "Arch CI"


def token():
    import jwt

    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["APPSTORE_ISSUER_ID"].strip(), "iat": now,
         "exp": now + 20 * 60, "aud": AUDIENCE},
        os.environ["APPSTORE_PRIVATE_KEY"],
        algorithm="ES256",
        headers={"kid": os.environ["APPSTORE_KEY_ID"].strip(), "typ": "JWT"},
    )


def call(method, path, bearer, body=None):
    request = urllib.request.Request(
        API + path,
        method=method,
        data=json.dumps(body).encode() if body else None,
        headers={
            "Authorization": "Bearer " + bearer,
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as problem:
        detail = problem.read().decode("utf-8", "replace")[:600]
        raise SystemExit("%s %s -> HTTP %d\n%s" % (method, path, problem.code, detail))


def run(args, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, **kwargs)
    if result.returncode != 0:
        print(result.stdout)
        print(result.stderr, file=sys.stderr)
        raise SystemExit("failed: " + " ".join(args))
    return result


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    bearer = token()

    # Clear out anything this tool made on a previous run. Apple allows three
    # distribution certificates and every one of ours is already useless -- its
    # private key existed only inside that run's machine.
    existing = call("GET", "/certificates?limit=200", bearer).get("data", [])
    mine = [
        row for row in existing
        if row.get("attributes", {}).get("certificateType") == "DISTRIBUTION"
        and LABEL in (row.get("attributes", {}).get("name") or "")
    ]
    for row in mine:
        call("DELETE", "/certificates/%s" % row["id"], bearer)
        print("revoked a previous %s certificate" % LABEL)

    others = [
        row for row in existing
        if row.get("attributes", {}).get("certificateType") == "DISTRIBUTION"
        and LABEL not in (row.get("attributes", {}).get("name") or "")
    ]
    if len(others) >= 3:
        raise SystemExit(
            "There are already three distribution certificates that this tool did "
            "not make, and Apple allows no more. Revoke one in the developer "
            "portal, or the archive cannot be signed."
        )

    key = os.path.join(out, "dist.key")
    csr = os.path.join(out, "dist.csr")
    # 2048-bit RSA: Apple refuses anything else for a signing certificate.
    run(["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes",
         "-keyout", key, "-out", csr,
         "-subj", "/CN=%s/O=Arch/C=US" % LABEL])

    with open(csr, "r", encoding="utf-8") as handle:
        csr_text = handle.read()

    created = call("POST", "/certificates", bearer, {
        "data": {
            "type": "certificates",
            "attributes": {
                "certificateType": "DISTRIBUTION",
                "csrContent": csr_text,
            },
        }
    })
    attributes = created["data"]["attributes"]
    print("created: %s  %s  expires %s" % (
        attributes.get("certificateType"),
        attributes.get("name"),
        (attributes.get("expirationDate") or "")[:10],
    ))

    cer = os.path.join(out, "dist.cer")
    with open(cer, "wb") as handle:
        handle.write(base64.b64decode(attributes["certificateContent"]))

    pem = os.path.join(out, "dist.pem")
    run(["openssl", "x509", "-inform", "DER", "-in", cer, "-out", pem])

    # A random passphrase per run. The .p12 exists for the length of one job and
    # is imported into a keychain that is deleted with the runner.
    passphrase = secrets.token_urlsafe(24)
    # Masked the moment it exists, not after it has been used -- a mask registered
    # later does not retroactively hide a line already written.
    if os.environ.get("GITHUB_ACTIONS"):
        print("::add-mask::%s" % passphrase)

    p12 = os.path.join(out, "dist.p12")
    # `-legacy` makes OpenSSL 3 write a .p12 that macOS's `security import` will
    # accept; LibreSSL, which is what /usr/bin/openssl is on a macOS runner, does
    # not know the flag at all. Try it, and fall back rather than guess which
    # openssl is first on the path.
    attempt = subprocess.run(
        ["openssl", "pkcs12", "-export", "-legacy",
         "-inkey", key, "-in", pem, "-out", p12,
         "-name", LABEL, "-passout", "pass:" + passphrase],
        capture_output=True, text=True,
    )
    if attempt.returncode != 0:
        print("openssl has no -legacy; using the default encoding")
        run(["openssl", "pkcs12", "-export",
             "-inkey", key, "-in", pem, "-out", p12,
             "-name", LABEL, "-passout", "pass:" + passphrase])

    with open(os.path.join(out, "p12.pass"), "w", encoding="utf-8") as handle:
        handle.write(passphrase)

    print("wrote %s (%d bytes)" % (p12, os.path.getsize(p12)))

    # The identity's common name, which is what CODE_SIGN_IDENTITY has to match.
    subject = run(["openssl", "x509", "-noout", "-subject", "-in", pem]).stdout.strip()
    print("subject: %s" % subject)

    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as handle:
            handle.write("p12=%s\n" % p12)
            handle.write("pass=%s\n" % passphrase)
    return 0


if __name__ == "__main__":
    sys.exit(main())
