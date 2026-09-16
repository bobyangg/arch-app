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
import urllib.error
import urllib.request

# A macOS build takes about seven minutes, and one with a TestFlight upload after
# it takes twenty. Ninety seconds is about fourteen calls to watch the long one,
# which leaves room inside the anonymous sixty-an-hour to read the result
# afterwards.
#
# Fifteen seconds was the first guess and spent the whole quota watching a build
# it could then not report on. Forty-five was the second, and was fine until a job
# ran for twenty minutes -- and a *second* watcher polling jobs and annotations
# alongside it emptied the budget again. The lesson both times: the cost is not
# the poll interval, it is calls-per-minute across everything running at once.
POLL = 90

REPO = "bobyangg/arch-app"
API = "https://api.github.com/repos/" + REPO


def get(path):
    request = urllib.request.Request(
        API + path, headers={"Accept": "application/vnd.github+json"}
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            remaining = response.headers.get("X-RateLimit-Remaining")
            if remaining is not None and int(remaining) < 8:
                print("  (%s API calls left this hour)" % remaining)
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code != 403:
            raise
        # Anonymous is sixty calls an hour for the whole machine, which a poll
        # every few seconds eats in minutes -- hence POLL below. Saying when it
        # comes back is more use than a stack trace.
        reset = error.headers.get("X-RateLimit-Reset")
        wait = max(0, int(reset) - int(time.time())) if reset else 0
        raise SystemExit(
            "GitHub is rate-limiting this machine (anonymous: 60/hour).\n"
            "It resets in %d minute(s). The run itself is unaffected." % (wait // 60 + 1)
        )


def head_sha():
    return subprocess.run(
        ["git", "rev-parse", "HEAD"], capture_output=True, text=True, check=True
    ).stdout.strip()


def run_for(sha, wait=True):
    """The workflow run for one commit, waiting for it to finish."""
    waited = 0
    while True:
        runs = get("/actions/runs?per_page=10")["workflow_runs"]
        # Prefix, not equality: a short sha is what `git log` prints and what
        # anybody types, and matching only the full forty characters made this
        # report "no run found" for a run that was sitting right there.
        mine = [r for r in runs if sha is None or r["head_sha"].startswith(sha)]
        if mine:
            run = mine[0]
            if run["status"] == "completed" or not wait:
                return run
            print("  %s (%ds)" % (run["status"], waited))
        elif not wait:
            return None
        else:
            print("  no run yet (%ds)" % waited)
        time.sleep(POLL)
        waited += POLL
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

    # Before anything else. A run that has not finished has proved nothing, and
    # every report below it is about a job still in flight -- which is how this
    # printed "nothing failed" for a build that was ten minutes from telling us
    # whether it worked. Same bug as the cancelled case, one state along.
    still_going = run["status"] != "completed"

    jobs = get("/actions/runs/%s/jobs" % run["id"])["jobs"]
    failed, unfinished = [], []
    for job in jobs:
        print("  %-28s %s" % (job["name"], job.get("conclusion")))
        if job.get("conclusion") == "failure":
            failed.append(job)
            for step in job.get("steps", []):
                if step.get("conclusion") == "failure":
                    print("      failed at: %s" % step["name"])
        elif job.get("conclusion") not in ("success", "skipped", None):
            # Cancelled, timed out, neutral. None of these are failures and none
            # of them are a pass -- and reporting "nothing failed" for a run that
            # never finished is the same quiet lie this tool exists to prevent.
            unfinished.append(job)

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
        # `buildwarnings.py` puts the complete list in one notice, because GitHub shows
        # only ten annotations of each level per step and a long warning list would
        # otherwise be silently cut off at ten.
        full = [
            clean(n)
            for n in notes
            if n.get("annotation_level") == "notice"
            and (n.get("title") or "") == "Every warning"
        ]
        # Any other notice is a step reporting a measurement rather than a
        # complaint -- what the screenshots looked like, for instance. Printed by
        # title, because filtering for one known title meant every notice added
        # later was collected and then silently dropped.
        others = [
            ((n.get("title") or "note"), clean(n))
            for n in notes
            if n.get("annotation_level") == "notice"
            and (n.get("title") or "") != "Every warning"
        ]

        if errors:
            print()
            print("  %d error(s) in %s:" % (len(errors), job["name"]))
            for error in errors:
                print("    - %s" % error[:300])

        body = full[0].replace("%0A", "\n").splitlines() if full else []
        if body:
            print()
            print("  %s -- %s" % (job["name"], body[0]))
            for line in body[1:]:
                print("    %s" % line[:300])

        # Not `elif`. `buildwarnings.py` emits its notice on every run, including
        # one with nothing in it, so an `elif` here hid every warning raised by any
        # *other* step in the same job -- which is all of the ones the simulator
        # launch reports. They come from a different step and are not in that list.
        listed = set(body[1:])
        extra = [
            (path, line, message) for path, line, message in warnings
            if not any(message in entry for entry in listed)
        ]
        if extra:
            print()
            print("  %d other warning(s) in %s:" % (len(extra), job["name"]))
            for path, line, message in extra:
                where = "%s:%s" % (path, line) if path else ""
                print("    - %s %s" % (where, message[:260]))

        for title, message in others:
            print()
            print("  %s:" % title)
            for line in message.replace("%0A", "\n").splitlines():
                print("    %s" % line[:300])

    if still_going:
        print()
        print("  Still running. Nothing here is a result yet.")
        return 3

    if unfinished and not failed:
        print()
        print("  This run did not finish: %s." %
              ", ".join("%s was %s" % (j["name"], j.get("conclusion")) for j in unfinished))
        print("  Nothing was proved either way. A newer push usually explains it —")
        print("  the workflow cancels an in-progress run when another lands.")
        return 2

    if not failed:
        print()
        print("  nothing failed.")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
