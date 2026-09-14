# -*- coding: utf-8 -*-
"""How many tests actually ran, out of an xcodebuild test log.

A test target that executes *zero* tests exits zero, and the step goes green. So
does one that runs all of them. This project has already shipped three checks
that quietly tested nothing, so "the tests passed" is not a claim worth making
without a count behind it.

    python3 tools/testreport.py test.log

Exits non-zero if it cannot find evidence that a single test ran, which turns the
silent-success case into a visible failure.
"""
import os
import re
import sys

# The classic xcodebuild line, printed once per suite and once for the run.
EXECUTED = re.compile(r"Executed (\d+) test[s]?, with (\d+) failure")
# Xcode's newer runner phrases it differently; catching both means this does not
# quietly stop working the day the runner image moves on.
NEWER = re.compile(r"Test run with (\d+) test[s]? (passed|failed)")
FAILURE = re.compile(r"^(.*): error: -\[(\S+) (\S+)\] : (.*)$")


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: testreport.py <test.log>")
    path = sys.argv[1]
    if not os.path.exists(path):
        # The build failed before the tests were reached. That is already a
        # failure somewhere above; repeating it here would just add a second red
        # step pointing at the wrong thing.
        print("no test log at %s -- the tests were never reached" % path)
        return 0

    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        log = handle.read()

    # Every suite reports its own total as well as the run reporting the whole,
    # so these are overlapping counts rather than separate ones. The largest is
    # the run.
    counts = [(int(n), int(f)) for n, f in EXECUTED.findall(log)]
    newer = [int(n) for n, _ in NEWER.findall(log)]
    ran = max([n for n, _ in counts] + newer + [0])
    failed = max([f for _, f in counts] + [0])

    failures = []
    for line in log.splitlines():
        match = FAILURE.match(line.strip())
        if match:
            _, suite, test, message = match.groups()
            failures.append("%s.%s -- %s" % (suite, test, message[:200]))

    print("%d test(s) ran, %d failed" % (ran, failed))
    for failure in sorted(set(failures)):
        print("  - %s" % failure)

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write("## Tests\n\n**%d ran, %d failed.**\n\n" % (ran, failed))
            for failure in sorted(set(failures)):
                handle.write("- %s\n" % failure)
        body = "%d test(s) ran, %d failed" % (ran, failed)
        if failures:
            body += "\n" + "\n".join(sorted(set(failures)))
        encoded = body.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print("::notice title=Tests::%s" % encoded)

    if ran == 0:
        # The whole point of this file. A suite that ran nothing is not a suite
        # that passed, and nothing else in the pipeline can tell the difference.
        print("::error::No tests ran at all. A test target that executes zero "
              "tests still exits zero, so this is a failure on purpose.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
