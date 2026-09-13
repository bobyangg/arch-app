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

#: `weight * grid[a][b]`, flattened per scored question, so scoring a pair is
#: thirteen list lookups rather than thirteen dictionary lookups and a multiply.
WEIGHTED = [
    [[tables.TABLES[qid]["weight"] * cell for cell in row]
     for row in tables.TABLES[qid]["grid"]]
    for qid in population.SCORED_IDS
]

#: Allowed-grids for q14/q15/q16, in the same order as `Person.reqs`.
REQ_GRIDS = [tables.REQUIREMENTS[qid] for qid in population.REQ_IDS]

#: The order the funnel reports them in.
FILTER_NAMES = ("orientation", "age", "distance", "requirements", "blocked", "paused")


def score(a, b):
    """A pair as one number. Higher is better; 12.870 is the real ceiling."""
    aa, ba = a.answers, b.answers
    total = 0.0
    for j in range(13):
        total += WEIGHTED[j][aa[j]][ba[j]]
    return total


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
