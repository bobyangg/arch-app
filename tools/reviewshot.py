# -*- coding: utf-8 -*-
"""Pull the App Review screenshot out of the UI test results.

`testPremiumScreenForAppReview` attaches a screenshot of the Premium screen,
taken only after it has checked the three prices are the ones on screen. It lands
inside `TestResults.xcresult`, which is a bundle nobody can open on a Windows
machine. This exports the attachments and copies the one that matters to a plain
PNG with a name a person can find:

    python3 tools/reviewshot.py TestResults.xcresult premium-for-app-review.png

Then reports its size as an annotation, because annotations are the one channel a
public repository shows without signing in -- and Apple wants at least 640 x 920.
"""
import glob
import json
import os
import shutil
import struct
import subprocess
import sys

NAME = "premium-for-app-review"


def main():
    bundle, out = sys.argv[1], sys.argv[2]
    export = "review-attachments"
    shutil.rmtree(export, ignore_errors=True)
    os.makedirs(export)

    result = subprocess.run(
        ["xcrun", "xcresulttool", "export", "attachments",
         "--path", bundle, "--output-path", export],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(result.stdout)
        print(result.stderr, file=sys.stderr)
        print("::warning title=App Review screenshot::could not export attachments from %s" % bundle)
        return

    # The manifest maps each exported file to the name the test gave it. Read it
    # loosely: its exact shape has changed between Xcode releases, and a name
    # match anywhere in an entry is enough to find the one file wanted.
    chosen = None
    manifest = os.path.join(export, "manifest.json")
    if os.path.exists(manifest):
        with open(manifest) as handle:
            text = handle.read()

        def walk(node):
            nonlocal chosen
            if isinstance(node, dict):
                values = json.dumps(node)
                exported = node.get("exportedFileName")
                if exported and NAME in values and exported.lower().endswith(".png"):
                    chosen = chosen or os.path.join(export, exported)
                for value in node.values():
                    walk(value)
            elif isinstance(node, list):
                for value in node:
                    walk(value)

        walk(json.loads(text))

    # Failing a manifest match, a file named after the attachment.
    if not chosen:
        named = [p for p in glob.glob(os.path.join(export, "**", "*.png"), recursive=True) if NAME in p]
        chosen = named[0] if named else None

    if not chosen:
        found = glob.glob(os.path.join(export, "**", "*"), recursive=True)
        print("exported:", found)
        print("::warning title=App Review screenshot::the test ran but no attachment named %s was found" % NAME)
        return

    shutil.copyfile(chosen, out)
    with open(out, "rb") as handle:
        head = handle.read(24)
    width, height = struct.unpack(">II", head[16:24])
    enough = width >= 640 and height >= 920
    print("::notice title=App Review screenshot::%s is %d x %d (%s). The three prices were "
          "checked on screen before it was taken. Download it from this run's artifacts: "
          "premium-for-app-review." % (out, width, height,
                                       "large enough for Apple" if enough else "SMALLER than Apple's 640 x 920"))


if __name__ == "__main__":
    main()
