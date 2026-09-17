# -*- coding: utf-8 -*-
"""The moderation desk. Reads reports, and acts on them.

    python tools/moderate.py queue                 what is waiting
    python tools/moderate.py show <report-id>      one report, with context
    python tools/moderate.py dismiss <id> "why"    no action needed
    python tools/moderate.py remove <id> --reason abuse
    python tools/moderate.py pause <id> --reason photos --days 7
    python tools/moderate.py appeals               appeals waiting to be read
    python tools/moderate.py history <account-id>  everything about one account

**Why this exists.** Reporting, blocking and removal are all built and all write
to the database, and until now *nothing read them back*. A report landed in a
table and stayed there. The app promises "reports go to a person, not a filter",
and Apple's rules for user-generated content require a way to act on them in
reasonable time -- so the promise needed somewhere to be kept.

**A command line rather than a web page, deliberately.** An admin page needs
somewhere to live, an authentication story of its own, and the service key
somewhere near a browser. That is three new ways to lose the whole database in
exchange for prettier output. This needs no hosting and no new surface.

Two variables, and neither belongs in the repository:

    export SUPABASE_URL=https://yourproject.supabase.co
    export SUPABASE_SERVICE_KEY=...        # Project Settings -> API -> service_role

**The service key bypasses row-level security entirely.** That is the point --
moderation has to see what the people involved cannot -- and it is also why it
lives in your shell and never in a file, a build setting or this repository.
"""
import argparse
import datetime
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

REMOVAL_REASONS = ["abuse", "photos", "underage", "selling", "other"]


def utcnow():
    """An ISO timestamp PostgREST will accept.

    Not the string "now()". PostgREST sends the JSON body to Postgres as values,
    not as SQL, so "now()" would be stored as those five characters and every
    later read would fail to parse it -- or worse, quietly sort wrong.
    """
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def config():
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_KEY", "")
    if not url or not key:
        raise SystemExit(
            "Set SUPABASE_URL and SUPABASE_SERVICE_KEY first.\n"
            "The service key is in Project Settings -> API -> service_role.\n"
            "It bypasses row-level security, so keep it in your shell and nowhere else."
        )
    return url, key


def rest(path, method="GET", body=None, prefer=None):
    url, key = config()
    request = urllib.request.Request(
        url + "/rest/v1/" + path,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={
            "apikey": key,
            "Authorization": "Bearer " + key,
            "Content-Type": "application/json",
            **({"Prefer": prefer} if prefer else {}),
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read()
            return json.loads(raw) if raw else []
    except urllib.error.HTTPError as problem:
        detail = problem.read().decode("utf-8", "replace")[:500]
        raise SystemExit("%s %s -> HTTP %d\n%s" % (method, path, problem.code, detail))


def when(value):
    return (value or "")[:16].replace("T", " ")


def short(value):
    """Enough of a uuid to recognise and to paste back."""
    return (value or "")[:8]


def find_one(table, prefix, extra=""):
    """A row by the first few characters of its id.

    Matched here rather than with `id=like.abc*`, which looks like it should work
    and returns 404: `id` is a `uuid` column, and Postgres will not compare a uuid
    to a pattern without a cast. Found by trying it rather than by reasoning about
    it -- the filter is accepted right up to the point where it is run.

    A moderation queue is small enough that fetching and matching here costs
    nothing, and it means a short id keeps working.
    """
    rows = rest("%s?select=*%s" % (table, extra))
    hits = [row for row in rows if row["id"].startswith(prefix)]
    if not hits:
        raise SystemExit("No %s starting %s." % (table[:-1], prefix))
    if len(hits) > 1:
        raise SystemExit(
            "%d rows start %s. Use more characters." % (len(hits), prefix))
    return hits[0]


# ---- reading ------------------------------------------------------------

def queue(args):
    state = "in.(new,reviewing)" if not args.all else "not.is.null"
    rows = rest("reports?state=%s&order=created_at.asc&select=*" % state)
    if not rows:
        print("Nothing waiting. (Reports appear here the moment somebody sends one.)")
        return 0

    print("%d report(s) waiting.\n" % len(rows))
    # Somebody reported several times, or by several people, is the signal worth
    # surfacing first -- one report is a disagreement, four is a pattern.
    counts = {}
    for row in rows:
        counts[row["reported_id"]] = counts.get(row["reported_id"], 0) + 1

    for row in rows:
        flag = ""
        if counts[row["reported_id"]] > 1:
            flag = "   <- %d reports about this account" % counts[row["reported_id"]]
        print("%s  %-10s  %s  reported %s%s" % (
            short(row["id"]), row["reason"], when(row["created_at"]),
            short(row["reported_id"]), flag))
        if row.get("note"):
            print("            \"%s\"" % row["note"][:100])
    print("\nNext: python tools/moderate.py show <report-id>")
    return 0


def show(args):
    report = find_one("reports", args.report)

    print("report    %s" % report["id"])
    print("reason    %s" % report["reason"])
    print("state     %s" % report["state"])
    print("made      %s" % when(report["created_at"]))
    if report.get("note"):
        print("note      %s" % report["note"])
    print()

    for label, account_id in [("reporter", report["reporter_id"]),
                              ("reported", report["reported_id"])]:
        accounts = rest("accounts?id=eq.%s&select=id,status,created_at,attested_at"
                        % account_id)
        account = accounts[0] if accounts else {}
        print("%-9s %s  status=%s  joined %s  attested=%s" % (
            label, short(account_id), account.get("status", "?"),
            when(account.get("created_at")),
            "yes" if account.get("attested_at") else "no"))

    # Everything else said about this account, because one report read alone is
    # the least informative way to read it.
    others = rest("reports?reported_id=eq.%s&select=id,reason,state,created_at"
                  % report["reported_id"])
    if len(others) > 1:
        print("\n%d report(s) about this account in total:" % len(others))
        for row in others:
            print("   %s  %-10s %-10s %s" % (
                short(row["id"]), row["reason"], row["state"], when(row["created_at"])))

    past = rest("removals?account_id=eq.%s&select=kind,reason,until,created_at"
                % report["reported_id"])
    if past:
        print("\nalready acted on %d time(s):" % len(past))
        for row in past:
            print("   %-8s %-9s %s" % (row["kind"], row["reason"], when(row["created_at"])))

    print("""
    dismiss   python tools/moderate.py dismiss %s "why"
    pause     python tools/moderate.py pause %s --reason photos --days 7
    remove    python tools/moderate.py remove %s --reason abuse""" % (
        short(report["id"]), short(report["id"]), short(report["id"])))
    return 0


def appeals(args):
    rows = rest("appeals?state=eq.submitted&order=created_at.asc&select=*")
    if not rows:
        print("No appeals waiting.")
        return 0
    print("%d appeal(s) waiting.\n" % len(rows))
    for row in rows:
        removal = rest("removals?id=eq.%s&select=account_id,kind,reason,created_at"
                       % row["removal_id"])
        info = removal[0] if removal else {}
        print("%s  appealing a %s for %s (%s)" % (
            short(row["id"]), info.get("kind", "?"), info.get("reason", "?"),
            when(info.get("created_at"))))
        print("      \"%s\"" % (row.get("body") or "")[:200])
        print()
    return 0


def history(args):
    account = args.account
    print("account %s\n" % account)
    # Prefix-matched here too, and for the same reason: these are uuid columns.
    for label, table, column in [
        ("reports against", "reports", "reported_id"),
        ("reports by", "reports", "reporter_id"),
        ("removals", "removals", "account_id"),
    ]:
        rows = [row for row in rest(table + "?select=*")
                if (row.get(column) or "").startswith(account)]
        print("%s: %d" % (label, len(rows)))
        for row in rows:
            print("   %s  %s" % (when(row.get("created_at")),
                                 row.get("reason") or row.get("kind")))
    return 0


# ---- acting -------------------------------------------------------------

def close_report(report_id, state, note):
    report = find_one("reports", report_id)
    rest("reports?id=eq.%s" % report["id"], method="PATCH", body={
        "state": state,
        "reviewer_note": note,
        "reviewed_at": utcnow(),
    })
    return report


def dismiss(args):
    report = close_report(args.report, "dismissed", args.note)
    print("Dismissed %s. Nobody is told, which is the same as every other outcome."
          % short(report["id"]))
    return 0


def act(args, kind):
    if args.reason not in REMOVAL_REASONS:
        raise SystemExit("reason must be one of: " + ", ".join(REMOVAL_REASONS))

    report = close_report(args.report, "actioned", args.note or kind)
    account_id = report["reported_id"]

    removal = {"account_id": account_id, "kind": kind, "reason": args.reason}
    if kind == "paused":
        if not args.days:
            raise SystemExit("A pause needs --days.")
        until = (datetime.datetime.now(datetime.timezone.utc)
                 + datetime.timedelta(days=args.days))
        removal["until"] = until.isoformat()

    # The removal row is what the app reads to draw the screen, and the account
    # status is what the rest of the schema reads. Both, or the person sees a
    # removal screen and still appears in rosters.
    rest("removals", method="POST", body=removal, prefer="return=representation")
    rest("accounts?id=eq.%s" % account_id, method="PATCH",
         body={"status": "removed" if kind == "removed" else "paused"})

    print("%s %s for %s." % (kind.capitalize(), short(account_id), args.reason))
    print("They see the screen on next launch, with the reason and an appeal.")
    print("The people they were talking to are not told why -- that is deliberate.")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Arch moderation")
    sub = parser.add_subparsers(dest="command", required=True)

    q = sub.add_parser("queue", help="reports waiting")
    q.add_argument("--all", action="store_true", help="including closed ones")
    q.set_defaults(run=queue)

    s = sub.add_parser("show", help="one report, with context")
    s.add_argument("report")
    s.set_defaults(run=show)

    d = sub.add_parser("dismiss", help="no action needed")
    d.add_argument("report")
    d.add_argument("note", nargs="?", default="")
    d.set_defaults(run=dismiss)

    for name, kind in [("remove", "removed"), ("pause", "paused")]:
        a = sub.add_parser(name, help="act on the reported account")
        a.add_argument("report")
        a.add_argument("--reason", required=True,
                       help="one of: " + ", ".join(REMOVAL_REASONS))
        a.add_argument("--days", type=int, help="for a pause")
        a.add_argument("--note", default="")
        a.set_defaults(run=lambda args, kind=kind: act(args, kind))

    ap = sub.add_parser("appeals", help="appeals waiting to be read")
    ap.set_defaults(run=appeals)

    h = sub.add_parser("history", help="everything about one account")
    h.add_argument("account")
    h.set_defaults(run=history)

    args = parser.parse_args()
    return args.run(args)


if __name__ == "__main__":
    sys.exit(main())
