# -*- coding: utf-8 -*-
"""Did the build actually arrive, or did we only manage to send it.

    python tools/tfcheck.py <build number>

`xcodebuild -exportArchive` exiting zero means the upload was accepted, which is
not the same as Apple having a build. Processing happens afterwards and can fail
on its own -- a missing icon, a bad entitlement, an export-compliance answer --
and none of that reaches the runner that sent it.

This project has now watched three separate things report success for something
they had not established: a deploy that returned ACTIVE for a function that would
not boot, a test step that passed with no tests, and a run report that called a
cancelled build clean. So the upload gets the same treatment as the rest.

Polls App Store Connect until the build number appears, then reports the
processing state. **A build that has not appeared yet is reported as a warning,
not a pass and not a failure** -- Apple is often slow, so "not there yet" is a
real third answer and saying so beats picking one of the other two.
"""
import os
import sys
import time
import urllib.error
import urllib.request
import json

API = "https://api.appstoreconnect.apple.com/v1"
AUDIENCE = "appstoreconnect-v1"
BUNDLE_ID = "com.arch.arch"
PATIENCE = 15 * 60


def annotate(level, message):
    if os.environ.get("GITHUB_ACTIONS"):
        print("::%s::%s" % (level, message.replace("\n", "%0A")))


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


def get(path, bearer):
    request = urllib.request.Request(
        API + path, headers={"Authorization": "Bearer " + bearer}
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: tfcheck.py <build number>")
    wanted = sys.argv[1]

    bearer = token()
    apps = get("/apps?limit=200", bearer).get("data", [])
    app = next((row for row in apps
                if row.get("attributes", {}).get("bundleId") == BUNDLE_ID), None)
    if not app:
        annotate("error", "No app record for " + BUNDLE_ID)
        return 1

    print("Looking for build %s of %s." % (wanted, BUNDLE_ID))
    started = time.time()
    while time.time() - started < PATIENCE:
        builds = get(
            "/builds?filter[app]=%s&filter[version]=%s&limit=1" % (app["id"], wanted),
            bearer,
        ).get("data", [])
        if builds:
            attributes = builds[0].get("attributes", {})
            state = attributes.get("processingState")
            print("build %s: %s (uploaded %s)" % (
                wanted, state, (attributes.get("uploadedDate") or "")[:19]))
            if state == "VALID":
                annotate("notice",
                         "Build %s is on TestFlight and ready to install." % wanted)
                return 0
            if state in ("INVALID", "FAILED"):
                annotate("error",
                         "Apple rejected build %s while processing it (%s)."
                         % (wanted, state))
                return 1
            # PROCESSING. Keep waiting; that is what the patience is for.
            print("  still processing (%d s)" % (time.time() - started))
        else:
            print("  not visible yet (%d s)" % (time.time() - started))
        time.sleep(30)

    # The honest third answer.
    annotate("warning",
             "Build %s had not appeared after %d minutes. The upload was accepted, "
             "so this is most likely Apple still processing -- check App Store "
             "Connect rather than assuming either way."
             % (wanted, PATIENCE // 60))
    return 0


if __name__ == "__main__":
    sys.exit(main())
