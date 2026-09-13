# -*- coding: utf-8 -*-
"""Who is even eligible, and how good the pair would be.

Every filter here is **mutual**. Arch pairs two people at once and spends a slot
from each, so a rule that holds in one direction only would produce a roster that
one of the two never agreed to.

The funnel is returned alongside the graph on purpose. "The median person has 180
candidates" is a fact; "orientation removed 61% and distance removed another 24%"
is something you can act on.
"""
from collections import Counter

import geo
import population
import tables

#: `weight * grid[a][b]`, in **thousandths, as integers**.
#:
#: Not a micro-optimisation -- a correctness requirement, and the single most
#: important line in this file.
#:
#: Floating-point addition is not associative, and this score is a sum of thirteen
#: terms. Python sums them left to right; SQL is free to associate them however the
#: planner likes. Measured on this population, **54% of pair scores differ between
#: forward and reverse summation of the identical thirteen terms** -- and because
#: scores sit on a coarse lattice where exact ties are everywhere, and ties are
#: broken by a hash, a one-ULP difference flips which candidate somebody takes.
#: Run end to end, that changed half the delivered pairs. Both outputs looked
#: perfectly plausible and nothing raised.
#:
#: Every `weight * cell` is exact at 1/1000 (weights have one decimal, cells have
#: two), so integers lose nothing and make the Python and the SQL comparable
#: exactly rather than approximately. The multiplication below is integer-only:
#: going via floats and rounding would reintroduce the thing it is avoiding.
WEIGHTED_MILLI = [
    [[int(round(tables.TABLES[qid]["weight"] * 10)) * int(round(cell * 100))
      for cell in row]
     for row in tables.TABLES[qid]["grid"]]
    for qid in population.SCORED_IDS
]

#: The same numbers as points, for anything that reports rather than ranks.
WEIGHTED = [[[v / 1000.0 for v in row] for row in grid] for grid in WEIGHTED_MILLI]

#: Allowed-grids for q14/q15/q16, in the same order as `Person.reqs`.
REQ_GRIDS = [tables.REQUIREMENTS[qid] for qid in population.REQ_IDS]

#: The order the funnel reports them in.
FILTER_NAMES = ("orientation", "age", "distance", "requirements", "blocked", "paused")


def score_milli(a, b):
    """A pair as one integer, in thousandths. The canonical score.

    Integer addition is associative, so this is the same number whoever adds it up
    and in whatever order -- which is what lets the SQL matcher be checked against
    this one for exact equality rather than for being close.
    """
    aa, ba = a.answers, b.answers
    total = 0
    for j in range(13):
        total += WEIGHTED_MILLI[j][aa[j]][ba[j]]
    return total


def score(a, b):
    """The same pair in points. Higher is better; 12.870 is the real ceiling.

    One division of an exact integer, so it is still reproducible -- the ordering
    decisions are all made on `score_milli`, and this is for reading.
    """
    return score_milli(a, b) / 1000.0


def orientation_ok(a, b):
    return b.gender in a.seeking and a.gender in b.seeking


def age_ok(a, b):
    return a.min_age <= b.age <= a.max_age and b.min_age <= a.age <= b.max_age


def distance_ok(a, b):
    return geo.within(geo.miles(a.point, b.point), a.distance, b.distance)


def requirements_ok(a, b):
    for j in range(3):
        if not REQ_GRIDS[j][a.reqs[j]][b.reqs[j]]:
            return False
    return True


def not_blocked(a, b):
    return b.pid not in a.blocks and a.pid not in b.blocks


def _both_active(a, b):
    return not a.paused and not b.paused


def eligible(a, b):
    """The first filter that rejects this pair, or None if it survives.

    Returning the *reason* is what makes the starvation section worth printing --
    a cohort with no matches is only actionable once you can say which rule made
    them unreachable.
    """
    if not orientation_ok(a, b):
        return "orientation"
    if not age_ok(a, b):
        return "age"
    if not distance_ok(a, b):
        return "distance"
    if not requirements_ok(a, b):
        return "requirements"
    if not not_blocked(a, b):
        return "blocked"
    if not _both_active(a, b):
        return "paused"
    return None


def build_static(people):
    """Everything that does not change from night to night.

    Orientation, age, distance, requirements, blocks and pauses are fixed for the
    run, so they are evaluated once over all pairs and reused. Only the cooldown
    and the slot accounting move nightly.

    Returns `(graph, funnel, rejections, scores)` where `graph[pid]` is a list of
    `(score, other_pid)` sorted best first, `funnel` counts survivors after each
    named filter, and `rejections[pid]` counts why this person lost candidates.
    """
    graph = dict((p.pid, []) for p in people)
    funnel = Counter()
    rejections = dict((p.pid, Counter()) for p in people)
    scores = {}
    n = len(people)

    funnel["all pairs"] = n * (n - 1) // 2
    for i in range(n):
        a = people[i]
        for j in range(i + 1, n):
            b = people[j]
            reason = eligible(a, b)
            if reason is not None:
                rejections[a.pid][reason] += 1
                rejections[b.pid][reason] += 1
                continue
            s = score(a, b)
            scores[(a.pid, b.pid)] = s
            graph[a.pid].append((s, b.pid))
            graph[b.pid].append((s, a.pid))
    funnel["eligible"] = sum(len(v) for v in graph.values()) // 2

    for pid in graph:
        graph[pid].sort(key=lambda t: -t[0])
    return graph, funnel, rejections, scores


def cumulative_funnel(people):
    """Survivors after each filter applied in order, for the report's §4 table.

    Deliberately a second pass rather than folded into `build_static`: the funnel
    wants *cumulative* survivors per stage, and the graph wants the first reason a
    pair died. Doing both in one loop made neither of them clear.
    """
    counts = Counter()
    n = len(people)
    counts["all pairs"] = n * (n - 1) // 2
    checks = (
        ("orientation", orientation_ok),
        ("age", age_ok),
        ("distance", distance_ok),
        ("requirements", requirements_ok),
        ("blocked", not_blocked),
        ("paused", _both_active),
    )
    for i in range(n):
        a = people[i]
        for j in range(i + 1, n):
            b = people[j]
            for name, fn in checks:
                if not fn(a, b):
                    break
                counts[name] += 1
    return counts
