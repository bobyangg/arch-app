# -*- coding: utf-8 -*-
"""Boot a simulator, install Arch, launch it, and see whether it is still there.

Compiling proves the types line up. It says nothing about whether the app *starts*
-- a force-unwrapped nil, a missing font, a precondition in a store's `init`, a
crash in `ArchSession.start()` are all clean compiles and a dead app. Sixteen
thousand lines of Swift had never been executed at all when this was written.

    python3 tools/simrun.py build/Build/Products/Debug-iphonesimulator/Arch.app

Fails the step if the app is not running some seconds after launch, and prints the
crash report and the simulator's log for the process when it is not.

Two screenshots are kept, one during the launch view and one well after it, and
they are the only pictures of Arch running that exist anywhere. The second is
also checked against the first: an app that is alive and stuck on its launch
view exits zero all day, and the way that shows up is a settled screen no
busier than the launch screen it should have replaced.
"""
import glob
import json
import os
import subprocess
import sys
import time

BUNDLE = "com.arch.arch"
SETTLE = 14   # seconds to let the app get past launch and draw something
FIRST_SHOT = 2  # the launch animation is about 1.4s, so this catches it mid-draw

# How much busier the settled screen has to be than the launch screen before we
# believe the app got past it. Generous on purpose: this only ever raises a
# warning, and a warning that cries wolf is worse than no warning.
FLAT_RATIO = 1.5


def run(args, check=True, quiet=False):
    if not quiet:
        print("$ " + " ".join(args))
    result = subprocess.run(args, capture_output=True, text=True)
    if check and result.returncode != 0:
        print(result.stdout)
        print(result.stderr, file=sys.stderr)
        raise SystemExit("failed: %s" % " ".join(args))
    return result


def version_of(runtime_id):
    """`...SimRuntime.iOS-18-6` -> (18, 6), for sorting."""
    tail = runtime_id.rsplit(".", 1)[-1]
    parts = tail.split("-")[1:]
    numbers = []
    for part in parts:
        try:
            numbers.append(int(part))
        except ValueError:
            numbers.append(0)
    return tuple(numbers) or (0,)


def pick_device():
    """The newest iOS runtime on the image, and an iPhone inside it."""
    listing = json.loads(
        run(["xcrun", "simctl", "list", "devices", "available", "-j"], quiet=True).stdout
    )["devices"]
    candidates = []
    for runtime, devices in listing.items():
        if "SimRuntime.iOS-" not in runtime:
            continue
        for device in devices:
            if device.get("isAvailable") and "iPhone" in device.get("name", ""):
                candidates.append((version_of(runtime), runtime, device))
    if not candidates:
        raise SystemExit("no available iPhone simulator on this image")
    # Newest runtime, and within it whichever iPhone the image happens to carry.
    candidates.sort(key=lambda item: item[0], reverse=True)
    _, runtime, device = candidates[0]
    print("runtime  %s" % runtime.rsplit(".", 1)[-1])
    print("device   %s  %s" % (device["name"], device["udid"]))
    return device["udid"]


def boot(udid):
    result = run(["xcrun", "simctl", "boot", udid], check=False)
    # Already booted is not a problem; anything else is.
    if result.returncode != 0 and "current state: Booted" not in (
        result.stdout + result.stderr
    ):
        print(result.stdout)
        print(result.stderr, file=sys.stderr)
        raise SystemExit("could not boot the simulator")
    run(["xcrun", "simctl", "bootstatus", udid, "-b"])


def crash_reports(since):
    """Crash logs written since we started, for our app."""
    found = []
    for pattern in ("Arch-*.ips", "Arch_*.ips"):
        base = os.path.expanduser("~/Library/Logs/DiagnosticReports")
        for path in glob.glob(os.path.join(base, pattern)):
            if os.path.getmtime(path) >= since:
                found.append(path)
    return found


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: simrun.py <path to Arch.app>")
    app = sys.argv[1]
    if not os.path.isdir(app):
        raise SystemExit("no app bundle at %s" % app)

    started = time.time()
    udid = pick_device()
    boot(udid)

    run(["xcrun", "simctl", "install", udid, app])

    launched = run(["xcrun", "simctl", "launch", "--terminate-running-process",
                    udid, BUNDLE])
    # `com.arch.arch: 45123`
    try:
        pid = int(launched.stdout.strip().split(":")[-1])
    except ValueError:
        print(launched.stdout)
        raise SystemExit("could not read a pid out of simctl launch")
    print("launched as pid %d" % pid)

    time.sleep(FIRST_SHOT)
    run(["xcrun", "simctl", "io", udid, "screenshot", "launching.png"], check=False)
    time.sleep(SETTLE - FIRST_SHOT)
    run(["xcrun", "simctl", "io", udid, "screenshot", "settled.png"], check=False)

    alive = subprocess.run(["ps", "-p", str(pid)], capture_output=True, text=True)
    still_running = alive.returncode == 0

    print()
    print("--- the simulator's log for Arch " + "-" * 40)
    log = run(
        ["xcrun", "simctl", "spawn", udid, "log", "show", "--last", "3m",
         "--predicate", 'process == "Arch"', "--style", "compact"],
        check=False, quiet=True,
    )
    lines = [line for line in log.stdout.splitlines() if line.strip()]
    for line in lines[-60:]:
        print("  " + line[:300])
    if not lines:
        print("  (nothing)")
    print("-" * 74)
    print()

    crashes = crash_reports(started)
    for path in crashes:
        print("--- crash report: %s" % os.path.basename(path))
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            for line in handle.read().splitlines()[:80]:
                print("  " + line[:300])

    run(["xcrun", "simctl", "shutdown", udid], check=False)

    if not still_running or crashes:
        print("::error::Arch did not survive launch on the simulator.")
        return 1

    # Alive is not the same as working, but the obvious test for that does not
    # work. Diffing the two screenshots cannot tell "stuck on the launch view"
    # from "working, and idle": the roster does not animate either, so both are a
    # still image eight seconds apart. What *does* separate them is how much is on
    # the screen. The launch view is one flat `ArchColor.night` field with a small
    # wordmark on it, and a flat field compresses to almost nothing, where a
    # roster of photographs and cards does not.
    def shot(name):
        if not os.path.exists(name):
            return 0
        return os.path.getsize(name)

    # The comparison is against `launching.png` rather than a byte count picked out
    # of the air, because that shot *is* a known-flat screen -- it is taken while
    # the launch view is still up. So the launch view calibrates the test for the
    # launch view, and there is no constant here to be wrong about on a device
    # whose screen is a different size.
    launching, settled = shot("launching.png"), shot("settled.png")
    print("screenshots: launching %d bytes, settled %d bytes" % (launching, settled))
    if launching and settled and settled < launching * FLAT_RATIO:
        print("::warning::The settled screen is no busier than the launch screen "
              "(%d bytes against %d) -- Arch may not have got past it. The two "
              "screenshots are on this run as an artifact." % (settled, launching))

    # Things that do not kill the process and are still worth knowing: a font that
    # did not register, an asset that would not load, an assertion that was logged
    # rather than trapped. None of these fail the step -- this is the first time
    # any of it has run, and a first read should report, not gate.
    trouble = [
        line for line in lines
        if any(word in line for word in
               ("Fatal", "fatal error", "Assertion", "Precondition", "unable to",
                "Unable to", "could not", "Could not", "failed", "Failed"))
    ]
    if trouble:
        print("%d log line(s) worth a look:" % len(trouble))
        for line in trouble[:10]:
            print("::warning::simulator log: %s" % line[:280])

    print("Arch was still running %d seconds after launch." % SETTLE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
