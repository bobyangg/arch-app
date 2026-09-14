# -*- coding: utf-8 -*-
"""What the compiler complained about, out of a build log.

`SWIFT_TREAT_WARNINGS_AS_ERRORS` is NO on purpose -- on a first build, treating
warnings as errors buries the real errors under them. The cost of that decision is
that a *successful* build throws its warnings away, which is how this project went
green while nobody knew whether it had two warnings or two hundred.

So they get counted, grouped and emitted as annotations. Annotations are the one
thing readable on a public repository without signing in -- **job summaries are
not**, which was checked against the API rather than assumed -- so this is the only
way the numbers reach anybody who is not holding a GitHub session.

    python3 tools/buildwarnings.py build.log

Run locally against a downloaded log and it just prints the table.
"""
import collections
import os
import re
import sys

# `path:line:col: warning: message`, which is both clang and swiftc. The path is
# non-greedy and anchored so that a message containing a colon does not eat it.
LOCATED = re.compile(r"^(.+?):(\d+):(\d+): warning: (.*)$")
# ld, xcodebuild and the asset catalogue have no file to point at.
BARE = re.compile(r"^(?:.*? )?warning: (.*)$")

PREFIX = "/Users/runner/work/arch-app/arch-app/"

# GitHub renders at most ten annotations of each level per step; emitting more just
# discards them silently.
ANNOTATION_LIMIT = 10


def normalise(message):
    """A warning's *kind*, for grouping.

    Identifiers are what differ between two instances of the same complaint, so
    'variable "a" was never used' and 'variable "b" was never used' collapse into
    one row with a count rather than filling the table with the same sentence.
    """
    return re.sub(r"'[^']*'", "'_'", message).strip()


def parse(path):
    seen = set()
    warnings = []
    with open(path, "r", encoding="utf-8", errors="replace") as log:
        for line in log:
            line = line.rstrip("\n")
            if ": warning: " not in line and not line.startswith("warning: "):
                continue
            match = LOCATED.match(line)
            if match:
                file, number, _, message = match.groups()
                file = file.replace(PREFIX, "")
                key = (file, number, message)
            else:
                match = BARE.match(line)
                if not match:
                    continue
                (message,) = match.groups()
                file, number = None, None
                key = (None, None, message)
            # A file compiled in more than one pass warns more than once about the
            # same line, and that is one warning, not several.
            if key in seen:
                continue
            seen.add(key)
            warnings.append((file, number, message))
    return warnings


def annotate(warnings):
    """Emit the workflow commands GitHub turns into annotations."""
    for file, number, message in warnings[:ANNOTATION_LIMIT]:
        if file:
            print("::warning file=%s,line=%s::%s" % (file, number, message))
        else:
            print("::warning::%s" % message)

    # Everything, in one notice, because the per-level cap is per level: the whole
    # list fits in a single annotation that `tools/ci.py` reads back in full.
    # Newlines inside an annotation message are percent-encoded; a literal percent
    # has to be encoded first or it eats the escape that follows it.
    lines = []
    for file, number, message in warnings:
        where = "%s:%s" % (file, number) if file else "(no file)"
        lines.append("%s  %s" % (where, message))
    body = "%d warning(s)\n%s" % (len(warnings), "\n".join(lines))
    encoded = body.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print("::notice title=Every warning::%s" % encoded)


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: warnings.py <build.log>")
    path = sys.argv[1]
    if not os.path.exists(path):
        print("no build log at %s -- nothing to read" % path)
        return 0

    warnings = parse(path)
    kinds = collections.Counter(normalise(message) for _, _, message in warnings)
    files = collections.Counter(file for file, _, _ in warnings if file)

    report = []
    report.append("## Warnings")
    report.append("")
    report.append("**%d distinct warning(s)** across %d file(s)."
                  % (len(warnings), len(files)))
    report.append("")
    if warnings:
        report.append("| count | warning |")
        report.append("|---:|---|")
        for kind, count in kinds.most_common(40):
            report.append("| %d | %s |" % (count, kind.replace("|", "\\|")))
        report.append("")
        report.append("| count | file |")
        report.append("|---:|---|")
        for file, count in files.most_common(20):
            report.append("| %d | `%s` |" % (count, file))

    text = "\n".join(report)
    print(text)

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(text + "\n")
        annotate(warnings)
    return 0


if __name__ == "__main__":
    sys.exit(main())
