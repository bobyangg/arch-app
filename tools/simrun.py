# -*- coding: utf-8 -*-
"""Boot a simulator, install Arch, launch it, and see whether it is still there.

Compiling proves the types line up. It says nothing about whether the app *starts*
-- a force-unwrapped nil, a missing font, a precondition in a store's `init`, a
crash in `ArchSession.start()` are all clean compiles and a dead app. Sixteen
thousand lines of Swift had never been executed at all when this was written.

    python3 tools/simrun.py build/Build/Products/Debug-iphonesimulator/Arch.app

Fails the step if the app is not running some seconds after launch, and prints the
crash report and the simulator's log for the process when it is not. Two
screenshots are taken -- one while the launch screen is up, one after it should
have gone -- because two identical images mean the app is alive and stuck, which no
exit code would ever tell you.
"""
import glob
import hashlib
import json
import os
import subprocess
import sys
import time

BUNDLE = "com.arch.arch"
SETTLE = 14  # seconds to let the app get past launch and draw something
FIRST_SHOT = 3


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

    # Alive is not the same as working. If the screen never changed, the app is
    # sitting on its launch view -- which is what a hang in `ArchSession.start()`
    # looks like from outside, and it exits zero all day.
    def shot(name):
        if not os.path.exists(name):
            return 0, None
        with open(name, "rb") as handle:
            data = handle.read()
        return len(data), hashlib.sha256(data).hexdigest()

    first, first_hash = shot("launching.png")
    second, second_hash = shot("settled.png")
    print("screenshots: launching %d bytes, settled %d bytes" % (first, second))
    if first_hash and first_hash == second_hash:
        print("::warning::The screen was identical %ds apart -- Arch launched but "
              "may not have got past its launch view." % (SETTLE - FIRST_SHOT))

    print("Arch was still running %d seconds after launch." % SETTLE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
