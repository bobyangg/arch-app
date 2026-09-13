# -*- coding: utf-8 -*-
"""One night's pairing.

**Not Gale-Shapley.** That solves a bipartite one-to-one problem with two sides.
This is one side, many-to-many, on a general graph -- the stable roommates problem,
which can simply have no stable solution. So it is rounds of proposals: each round
every unfilled person takes their best still-available candidate, scarcest first.

The result is not guaranteed optimal and does not need to be. It needs to be
mutual, to respect capacity, and to be better than chance -- and the report
measures that last one against a null matcher rather than asserting it.
"""
import hashlib


def tiebreak(seed, a, b):
    """A stable, seeded ordering for pairs that score identically.

    Scores live on a coarse lattice, so exact ties are common. Falling back to id
    order would let alphabetically-early people win every tie, which quietly biases
    the degree distribution, roster composition and the starvation cohort all at
    once. `hash()` will not do -- it is salted per process, so the run stops being
    reproducible.

    **SHA-256 rather than blake2b, because Postgres has neither `hash()` nor
    blake2b but does have `extensions.digest(..., 'sha256')`.** The nightly matcher
    runs in the database, and a tiebreak this program could compute and the
    database could not would make the two impossible to compare -- which is the
    whole point of keeping this file. Returned as raw bytes, which sort
    lexicographically in Python and as `bytea` in Postgres identically.
    """
    lo, hi = (a, b) if a < b else (b, a)
    key = ("%s|%s|%s" % (seed, lo, hi)).encode("utf-8")
    return hashlib.sha256(key).digest()


def sort_graph(graph, seed):
    """Best first, ties broken by the seeded digest rather than by id."""
    for pid, edges in graph.items():
        edges.sort(key=lambda e: (-e[0], tiebreak(seed, pid, e[1])))
    return graph


def match_night(graph, need, seen, night, cfg, seed, scorer=None):
    """Pair everybody up for one night.

    `need` is open slots *tonight* -- capacity minus whatever the person is still
    holding from yesterday -- not capacity. `seen[pid]` maps a previously-met pid
    to the night it happened, and the cooldown keeps them out.

    `scorer` overrides the edge ordering and exists for one reason: the null
    matcher in the report, which runs this identical algorithm on identical
    candidates with the scores replaced by noise. Without that comparison, "matched
    pairs score well" is circular and means nothing.
    """
    order_source = graph if scorer is None else scorer
    filled = dict((pid, 0) for pid in need)
    pointer = dict((pid, 0) for pid in need)
    paired = dict((pid, set()) for pid in need)
    pairs = []

    def blocked_tonight(pid, other):
        if filled[other] >= need[other]:
            return True
        if other in paired[pid]:
            return True
        last = seen[pid].get(other)
        if last is not None and cfg.cooldown and night - last <= cfg.cooldown:
            return True
        return False

    def advance(pid):
        """Move past candidates who can never become available tonight.

        Every reason above is permanent for the night -- a full person does not
        empty, a cooldown does not lapse mid-run -- so the pointer only ever moves
        forward and the whole night stays linear in the number of edges.
        """
        edges = order_source[pid]
        i = pointer[pid]
        while i < len(edges) and blocked_tonight(pid, edges[i][1]):
            i += 1
        pointer[pid] = i
        return i

    def live(pid):
        i = advance(pid)
        edges = order_source[pid]
        return sum(1 for k in range(i, len(edges))
                   if not blocked_tonight(pid, edges[k][1]))

    rounds = max(need.values()) if need else 0
    for _ in range(rounds):
        candidates = [pid for pid in need if filled[pid] < need[pid] and live(pid)]
        if not candidates:
            break
        candidates.sort(key=lambda p: (live(p), filled[p], tiebreak(seed, p, p)))

        for p in candidates:
            if filled[p] >= need[p]:
                continue
            i = advance(p)
            if i >= len(order_source[p]):
                continue
            q = order_source[p][i][1]
            if blocked_tonight(p, q):
                continue
            filled[p] += 1
            filled[q] += 1
            paired[p].add(q)
            paired[q].add(p)
            pairs.append((p, q))

    return pairs, filled


def shadow_demand(graph, need):
    """How many people would hold each person in their top-k with no constraints.

    The literal question -- does mutual pairing cap somebody at their capacity --
    is a tautology, since pairing spends a slot at both ends. The real question is
    what the cap costs: if a handful of people are wanted by two hundred others,
    the cap is doing enormous work and everybody it turns away is a candidate for
    the starving cohort. That is invisible in the delivered numbers.
    """
    demand = dict((pid, 0) for pid in graph)
    for pid, edges in graph.items():
        for _, other in edges[:need.get(pid, 0)]:
            demand[other] += 1
    return demand
