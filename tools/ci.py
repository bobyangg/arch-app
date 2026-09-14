# -*- coding: utf-8 -*-
"""What CI said about the current commit.

GitHub gates Actions *logs* behind a sign-in even on a public repository, but it
does not gate *annotations* — so the workflow emits every compile error as one,
and this reads them back without a token.

    python tools/ci.py           the run for HEAD, waiting if it is still going
    python tools/ci.py --sha X   a particular commit
    python tools/ci.py --last    whatever ran most recently, HEAD or not

Written as a file rather than a shell one-liner after three goes at the latter:
`/tmp` does not mean the same thing to Git Bash and to Windows Python, an
un-exported variable is invisible to a subprocess, and the newest completed run is
not necessarily the run for the commit you just pushed.
"""
import argparse
import json
import subprocess
import sys
import time
import urllib.request

REPO = "bobyangg/arch-app"
API = "https://api.github.com/repos/" + REPO


def get(path):
    request = urllib.request.Request(
        API + path, headers={"Accept": "application/vnd.github+json"}
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def head_sha():
    return subprocess.run(
        ["git", "rev-parse", "HEAD"], capture_output=True, text=True, check=True
    ).stdout.strip()


def run_for(sha, wait=True):
    """The workflow run for one commit, waiting for it to finish."""
    waited = 0
    while True:
        runs = get("/actions/runs?per_page=10")["workflow_runs"]
        mine = [r for r in runs if sha is None or r["head_sha"] == sha]
        if mine:
            run = mine[0]
            if run["status"] == "completed" or not wait:
                return run
            print("  %s (%ds)" % (run["status"], waited))
        elif not wait:
            return None
        else:
            print("  no run yet (%ds)" % waited)
        time.sleep(15)
        waited += 15
        if waited > 900:
            raise SystemExit("gave up waiting after fifteen minutes")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sha")
    parser.add_argument("--last", action="store_true")
    parser.add_argument("--no-wait", action="store_true")
    args = parser.parse_args()

    sha = None if args.last else (args.sha or head_sha())
    if sha:
        print("commit %s" % sha[:8])

    run = run_for(sha, wait=not args.no_wait)
    if run is None:
        print("no run found")
        return 1

    print()
    print("%s  %s / %s" % (run["id"], run["status"], run.get("conclusion")))
    print(run["html_url"])
    print()

    jobs = get("/actions/runs/%s/jobs" % run["id"])["jobs"]
    failed = []
    for job in jobs:
        print("  %-28s %s" % (job["name"], job.get("conclusion")))
        if job.get("conclusion") == "failure":
            failed.append(job)
            for step in job.get("steps", []):
                if step.get("conclusion") == "failure":
                    print("      failed at: %s" % step["name"])

    prefix = "/Users/runner/work/arch-app/arch-app/"

    def clean(note):
        return note.get("message", "").strip().replace(prefix, "")

    # Annotations are fetched for every job, not only failed ones: a green build
    # still carries its warnings, and those are the whole reason this reads
    # annotations rather than logs.
    for job in jobs:
        notes = get("/check-runs/%s/annotations" % job["id"])
        errors = [clean(n) for n in notes if n.get("annotation_level") == "failure"]
        # The workflow's own "process completed with exit code" line is the shell
        # reporting that something failed, which is already obvious from the job.
        errors = [e for e in errors if "Process completed with exit code" not in e]
        warnings = [
            (n.get("path"), n.get("start_line"), clean(n))
            for n in notes
            if n.get("annotation_level") == "warning"
        ]
        # `warnings.py` puts the complete list in one notice, because GitHub shows
        # only ten annotations of each level per step and a long warning list would
        # otherwise be silently cut off at ten.
        full = [
            clean(n)
            for n in notes
            if n.get("annotation_level") == "notice"
            and (n.get("title") or "") == "Every warning"
        ]

        if errors:
            print()
            print("  %d error(s) in %s:" % (len(errors), job["name"]))
            for error in errors:
                print("    - %s" % error[:300])

        if full:
            body = full[0].replace("%0A", "\n").splitlines()
            print()
            print("  %s -- %s" % (job["name"], body[0] if body else ""))
            for line in body[1:]:
                print("    %s" % line[:300])
        elif warnings:
            print()
            print("  %d warning(s) in %s:" % (len(warnings), job["name"]))
            for path, line, message in warnings:
                where = "%s:%s" % (path, line) if path else ""
                print("    - %s %s" % (where, message[:260]))

    if not failed:
        print()
        print("  nothing failed.")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
