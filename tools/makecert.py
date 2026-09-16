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
import re
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
PROFILE_NAME = "Arch CI App Store"
BUNDLE_ID = "com.arch.arch"


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
        message = "%s %s -> HTTP %d\n%s" % (method, path, problem.code, detail)
        # **As an annotation as well.** This step failed once with nothing but
        # "process completed with exit code 1" visible, because the detail went to
        # stderr and GitHub gates the log behind a sign-in. Annotations are the
        # readable channel; a diagnostic nobody can read is not a diagnostic.
        if os.environ.get("GITHUB_ACTIONS"):
            print("::error::makecert: " + message.replace("\n", "%0A"))
        raise SystemExit(message)


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

    # Clear out the previous run's certificates.
    #
    # **Not matched by name, because Apple ignores the one we ask for.** The CSR
    # says "Arch CI" and Apple names the certificate after the account holder --
    # "Apple Distribution: Alwin Ning" -- so a name test matched nothing, revoked
    # nothing, and would have let them pile up until the limit of three stopped
    # the build with something obscure.
    #
    # So: every distribution certificate goes before a new one is made. That is
    # safe here for a specific reason rather than by luck -- the private key never
    # leaves the runner that made it, so every certificate at Apple can already
    # sign nothing. Revoking them destroys nothing that works.
    #
    # If a Mac ever joins this project and somebody makes a certificate they
    # actually hold the key for, set KEEP_CERTS=1 and this stops.
    existing = call("GET", "/certificates?limit=200", bearer).get("data", [])

    if os.environ.get("KEEP_CERTS"):
        print("KEEP_CERTS is set; leaving existing certificates alone")
    else:
        for row in existing:
            attributes = row.get("attributes", {})
            kind = attributes.get("certificateType")
            name = attributes.get("name") or ""
            # Development certificates too: `-allowProvisioningUpdates` made two
            # while automatic signing was being tried, and their keys are equally
            # gone. "Created via API" keeps this away from anything Xcode made on
            # somebody's own machine.
            if kind == "DISTRIBUTION" or (
                kind == "DEVELOPMENT" and "Created via API" in name
            ):
                try:
                    call("DELETE", "/certificates/%s" % row["id"], bearer)
                    print("revoked %s (%s)" % (kind, name[:40]))
                except SystemExit as problem:
                    # One that will not delete is not worth stopping for -- the
                    # limit is three and we are clearing several.
                    print("could not revoke %s: %s" % (name[:40], problem))


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

    # ---- and the provisioning profile ------------------------------------
    #
    # Automatic signing was asked three times and chose a *development* profile
    # every time, even with a distribution certificate sitting right there:
    # `xcodebuild` does not infer "this archive is for the App Store" the way the
    # Xcode application does. So the profile is made here too, and the build signs
    # manually — which takes the guessing out of it entirely.
    cert_id = created["data"]["id"]

    bundles = call("GET", "/bundleIds?limit=200", bearer).get("data", [])
    bundle = next((row for row in bundles
                   if row.get("attributes", {}).get("identifier") == BUNDLE_ID), None)
    if not bundle:
        raise SystemExit("No registered bundle id %s to attach a profile to." % BUNDLE_ID)

    # A profile is bound to the certificates it was made with, so last run's is
    # useless the moment its certificate is revoked. Clear ours out by name.
    for row in call("GET", "/profiles?limit=200", bearer).get("data", []):
        if row.get("attributes", {}).get("name") == PROFILE_NAME:
            call("DELETE", "/profiles/%s" % row["id"], bearer)
            print("removed the previous %s profile" % PROFILE_NAME)

    profile = call("POST", "/profiles", bearer, {
        "data": {
            "type": "profiles",
            "attributes": {"name": PROFILE_NAME, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"id": bundle["id"], "type": "bundleIds"}},
                "certificates": {"data": [{"id": cert_id, "type": "certificates"}]},
            },
        }
    })
    content = base64.b64decode(profile["data"]["attributes"]["profileContent"])

    # The UUID sits in the plist inside the CMS envelope. Read with a regex rather
    # than `security cms`, which exists only on a Mac — this way the tool can be
    # run and reasoned about anywhere.
    match = re.search(rb"<key>UUID</key>\s*<string>([0-9A-Fa-f-]+)</string>", content)
    if not match:
        raise SystemExit("Could not find the UUID inside the profile.")
    uuid = match.group(1).decode()

    # Both locations: the second is where Xcode 16 and later look, and which Xcode
    # is newest is decided by the runner image rather than by us.
    for folder in [
        os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles"),
        os.path.expanduser("~/Library/Developer/Xcode/UserData/Provisioning Profiles"),
    ]:
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, uuid + ".mobileprovision"), "wb") as handle:
            handle.write(content)

    print("profile: %s  (%s)" % (PROFILE_NAME, uuid))

    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as handle:
            handle.write("p12=%s\n" % p12)
            handle.write("pass=%s\n" % passphrase)
            handle.write("profile=%s\n" % PROFILE_NAME)
            handle.write("uuid=%s\n" % uuid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
