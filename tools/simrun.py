# -*- coding: utf-8 -*-
"""Boot a simulator, install Arch, launch it, and see whether it is still there.

Compiling proves the types line up. It says nothing about whether the app *starts*
-- a force-unwrapped nil, a missing font, a precondition in a store's `init`, a
crash in `ArchSession.start()` are all clean compiles and a dead app. Sixteen
thousand lines of Swift had never been executed at all when this was written.

    python3 tools/simrun.py build/Build/Products/Debug-iphonesimulator/Arch.app

Fails the step if the app is not running some seconds after launch, and prints the
crash report and the simulator's log for the process when it is not.

Three screenshots are kept -- before the launch, during it, and well after --
and they are the only pictures of Arch running that exist anywhere. The last is
checked against the *first*, not against the one during launch: an app that is
alive but never came to the foreground exits zero all day, and that is the thing
a screenshot can actually settle. Comparing against the launch view cannot be
made to work, because the launch animation is over in 1.4 seconds and any shot
late enough to prove the app drew is too late to catch it.

Each is also averaged down to a single pixel, which separates a near-white screen
from a dark one where a byte count cannot.
"""
import glob
import json
import os
import struct
import subprocess
import sys
import time
import zlib

BUNDLE = "com.arch.arch"
SETTLE = 14     # seconds to let the app get past launch and draw something
FIRST_SHOT = 2  # the launch animation is about 1.4s; this lands near the end of it


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


def average_colour(path):
    """The whole screenshot averaged down to one pixel.

    `sips` is stock on macOS, and scaling to 1x1 is an average of every pixel in
    the image. A 1x1 PNG is then trivial to decode with nothing installed: one
    filter byte and the samples, and with no left or upper neighbour every filter
    predicts zero, so the bytes are the values whatever filter was chosen.

    Cheap, and it says something a byte count cannot -- a near-white screen and a
    dark one can compress to the same size.
    """
    tiny = path + ".1x1.png"
    if run(["sips", "-z", "1", "1", path, "--out", tiny],
           check=False, quiet=True).returncode != 0:
        return None
    try:
        with open(tiny, "rb") as handle:
            data = handle.read()
    except OSError:
        return None

    position, idat, colour_type = 8, b"", 2
    while position + 8 <= len(data):
        length = struct.unpack(">I", data[position:position + 4])[0]
        kind = data[position + 4:position + 8]
        chunk = data[position + 8:position + 8 + length]
        if kind == b"IHDR":
            colour_type = chunk[9]
        elif kind == b"IDAT":
            idat += chunk
        position += 12 + length
    if not idat:
        return None
    raw = zlib.decompress(idat)[1:]          # drop the filter byte
    if colour_type in (2, 6) and len(raw) >= 3:
        return tuple(raw[:3])
    if colour_type in (0, 4) and len(raw) >= 1:
        return (raw[0],) * 3
    return None


def describe(name):
    """Size and average colour of a screenshot, as a line for the log."""
    if not os.path.exists(name):
        return name, 0, None, "missing"
    size = os.path.getsize(name)
    colour = average_colour(name)
    shown = "#%02x%02x%02x" % colour if colour else "unreadable"
    return name, size, colour, "%7d bytes   average %s" % (size, shown)


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

    # Taken before the app is launched, and the whole reason the check below can
    # work. Comparing the settled screen against the *launch view* cannot be made
    # reliable -- the launch animation is over in 1.4 seconds, so any shot late
    # enough to be sure the app has drawn is also too late to catch it, and the
    # comparison collapses into "is a static roster static", which it always is.
    # Comparing against what was on screen before Arch opened has no such race.
    run(["xcrun", "simctl", "io", udid, "screenshot", "before.png"], check=False)

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

    # Alive is not the same as on screen. A process that launched, drew nothing
    # and sat there is still a process.
    measurements = [describe(name) for name in
                    ("before.png", "launching.png", "settled.png")]
    print("screenshots:")
    for name, _, _, line in measurements:
        print("  %-14s %s" % (name, line))

    before, settled = measurements[0], measurements[2]
    if before[1] and settled[1] and before[1] == settled[1] and before[2] == settled[2]:
        print("::warning::The screen fourteen seconds after launch is identical to "
              "the one taken before Arch was started -- it may never have come to "
              "the foreground. The screenshots are on this run as an artifact.")

    # Reported, not judged. Two identical frames twelve seconds apart is what a
    # working idle roster looks like as well as a stuck one, so these are evidence
    # for a person to read rather than a threshold to trip.
    print("::notice title=What was on screen::%s" % "%0A".join(
        "%s  %s" % (name, line) for name, _, _, line in measurements))

    # Things that do not kill the process and are still worth knowing: a font that
    # did not register, an asset that would not load, an assertion that was logged
    # rather than trapped. None of these fail the step -- this is the first time
    # any of it has run, and a first read should report, not gate.
    # A scan that matched nothing and a scan that had nothing to match look exactly
    # the same from out here, and the second one is a check quietly testing
    # nothing. Say which it was.
    if not lines:
        print("::warning::The simulator log predicate matched no lines at all, so "
              "the scan below proved nothing. Either Arch logged nothing in three "
              "minutes, or the predicate does not name the process correctly.")

    # Two passes, because the first version of this matched on "Assertion" and
    # duly reported every line mentioning BKSProcessAssertion -- a class name, in
    # the ordinary course of a launch. Substring matching on a word that appears
    # inside an identifier reports the identifier.
    NOISE = ("com.apple.UIKit:BackgroundTask", "com.apple.app_launch_measurement")
    TROUBLE = ("Fatal error", "fatal error", "Assertion failed", "assertion failed",
               "Precondition failed", "precondition failure", "unrecognized selector",
               "Unable to load", "unable to load", "Could not load", "could not load",
               "Failed to load", "failed to load", "Unable to register",
               "failed to register", "No such file")
    trouble = [
        line for line in lines
        if not any(subsystem in line for subsystem in NOISE)
        and any(phrase in line for phrase in TROUBLE)
    ]
    if trouble:
        print("%d log line(s) worth a look:" % len(trouble))
        for line in trouble[:10]:
            print("::warning::simulator log: %s" % line[:280])

    print("Arch was still running %d seconds after launch." % SETTLE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
