# -*- coding: utf-8 -*-
"""Can CI actually talk to App Store Connect, and is the app really there.

    python tools/ascheck.py

Reads `APPSTORE_ISSUER_ID`, `APPSTORE_KEY_ID` and `APPSTORE_PRIVATE_KEY` from the
environment, signs an ES256 token the way App Store Connect requires, and asks for
the list of apps.

**This is deliberately the first thing the signing work does.** Every later step —
provisioning, signing, uploading to TestFlight — depends on all three secrets
being right, and each of them fails with a different unhelpful message twenty
minutes into a macOS build. Asking Apple directly, on a cheap Ubuntu runner,
turns four possible mysteries into one plain answer:

  - a missing secret says which one,
  - a bad key fails at signing, before any request goes out,
  - a wrong issuer id comes back 401,
  - and a missing app record comes back as a list without the bundle id in it.

Nothing here prints any key material. The token it mints lasts twenty minutes,
which is Apple's maximum, and is thrown away.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

BUNDLE_ID = "com.arch.arch"
AUDIENCE = "appstoreconnect-v1"
API = "https://api.appstoreconnect.apple.com/v1"

NEEDED = ["APPSTORE_ISSUER_ID", "APPSTORE_KEY_ID", "APPSTORE_PRIVATE_KEY"]


def annotate(level, message):
    """A workflow annotation, which is readable without signing in to GitHub."""
    if os.environ.get("GITHUB_ACTIONS"):
        print("::%s::%s" % (level, message.replace("\n", "%0A")))


def token(issuer, key_id, private_key):
    import jwt  # pyjwt[crypto]; installed by the workflow

    now = int(time.time())
    return jwt.encode(
        # `exp` is capped at twenty minutes by Apple and rejected beyond it.
        {"iss": issuer, "iat": now, "exp": now + 20 * 60, "aud": AUDIENCE},
        private_key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def get(path, bearer):
    request = urllib.request.Request(
        API + path, headers={"Authorization": "Bearer " + bearer}
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def main():
    missing = [name for name in NEEDED if not os.environ.get(name)]
    if missing:
        # Not a pass, and not silently skipped. A check that says nothing when it
        # cannot run is the failure this repository keeps finding in itself.
        print("These secrets are not set on the repository:")
        for name in missing:
            print("    %s" % name)
        print()
        print("Set them at Settings -> Secrets and variables -> Actions.")
        annotate("error", "App Store Connect secrets missing: " + ", ".join(missing))
        return 1

    issuer = os.environ["APPSTORE_ISSUER_ID"].strip()
    key_id = os.environ["APPSTORE_KEY_ID"].strip()
    key = os.environ["APPSTORE_PRIVATE_KEY"]

    print("issuer  %s" % issuer)
    print("key id  %s" % key_id)
    print("key     %d characters, %s" % (
        len(key),
        "PEM armour present" if "BEGIN PRIVATE KEY" in key else "NO PEM ARMOUR",
    ))
    print()

    if "BEGIN PRIVATE KEY" not in key:
        print("The private key has no -----BEGIN PRIVATE KEY----- line.")
        print("Paste the whole .p8 file, armour lines included.")
        annotate("error", "APPSTORE_PRIVATE_KEY is not a PEM private key")
        return 1

    try:
        bearer = token(issuer, key_id, key)
    except Exception as problem:
        print("The key would not sign: %s" % problem)
        annotate("error", "APPSTORE_PRIVATE_KEY will not sign: %s" % problem)
        return 1

    try:
        apps = get("/apps?limit=200", bearer)
    except urllib.error.HTTPError as problem:
        body = problem.read().decode("utf-8", "replace")[:400]
        print("App Store Connect refused the request: HTTP %d" % problem.code)
        print(body)
        if problem.code == 401:
            print()
            print("401 almost always means the issuer id or the key id is wrong,")
            print("or the key has been revoked. The key itself signed fine.")
        annotate("error", "App Store Connect returned %d" % problem.code)
        return 1

    rows = apps.get("data", [])
    print("App Store Connect answered. %d app(s) on the account:" % len(rows))
    found = None
    for row in rows:
        attributes = row.get("attributes", {})
        bundle = attributes.get("bundleId")
        print("    %-34s %s" % (bundle, attributes.get("name")))
        if bundle == BUNDLE_ID:
            found = row

    print()
    if not found:
        print("No app record for %s." % BUNDLE_ID)
        print("Create it at App Store Connect -> Apps -> + -> New App, choosing")
        print("that bundle id from the dropdown.")
        annotate("error", "No App Store Connect app record for " + BUNDLE_ID)
        return 1

    print("Found %s -- \"%s\" (id %s)." % (
        BUNDLE_ID, found["attributes"].get("name"), found["id"]))
    print("All three secrets work and the app record exists.")
    annotate("notice", "App Store Connect reachable; %s is registered as \"%s\""
             % (BUNDLE_ID, found["attributes"].get("name")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
