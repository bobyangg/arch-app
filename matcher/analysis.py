# -*- coding: utf-8 -*-
"""Turning a run into the numbers that decide something.

Pure functions, no printing. The one rule the whole module is built around:

**A matcher that maximises score will always report that matched pairs score well.**
That is circular and proves nothing. Every claim about discrimination here is made
against something -- a shuffled table, a mechanical rule, or the same matcher run on
noise -- because a number with nothing to compare it to is decoration.
"""
import math
import random
import statistics as st

import filters
import match
import night as night_mod
import population
import tables

K_DEFAULT = 5


# ---------------------------------------------------------------- table geometry

def table_geometry():
    """Exact facts about the 95 numbers. No simulation involved."""
    cells = sum(len(t["grid"]) ** 2 for t in tables.TABLES.values())
    unique = sum(len(t["grid"]) * (len(t["grid"]) + 1) // 2
                 for t in tables.TABLES.values())
    return {
        "weights_sum": tables.MAX_SCORE,
        "attainable_max": tables.ATTAINABLE_MAX,
        "attainable_min": tables.ATTAINABLE_MIN,
        "span": tables.ATTAINABLE_MAX - tables.ATTAINABLE_MIN,
        "cells": cells,
        "unique": unique,
        "numbers": unique + len(tables.TABLES),
        "no_perfect": [qid for qid, t in tables.TABLES.items()
                       if max(max(r) for r in t["grid"]) < 1.0],
    }


def uniform_moments():
    """Mean and sd of a pair score if everybody answered at random.

    Each question is independent, so the total's variance is the sum of theirs --
    no sampling needed, and no sampling error to argue about.
    """
    mean = 0.0
    var = 0.0
    shares = []
    for qid in population.SCORED_IDS:
        t = tables.TABLES[qid]
        w, grid = t["weight"], t["grid"]
        n = len(grid)
        vals = [w * grid[i][j] for i in range(n) for j in range(n)]
        m = sum(vals) / len(vals)
        v = sum((x - m) ** 2 for x in vals) / len(vals)
        mean += m
        var += v
        shares.append((qid, w, v))
    total = var or 1.0
    shares = [(qid, w, v / total) for qid, w, v in shares]
    shares.sort(key=lambda r: -r[2])
    return {"mean": mean, "sd": math.sqrt(var), "shares": shares}


def score_distribution(people, sample=40000, seed=1):
    """Percentiles of the pair score over randomly drawn pairs."""
    rng = random.Random(seed)
    vals = []
    n = len(people)
    for _ in range(sample):
        a = people[rng.randrange(n)]
        b = people[rng.randrange(n)]
        if a is b:
            continue
        vals.append(filters.score(a, b))
    vals.sort()

    def pct(p):
        return vals[min(len(vals) - 1, int(p * len(vals)))]

    return {
        "mean": st.fmean(vals), "sd": st.pstdev(vals),
        "p1": pct(0.01), "p5": pct(0.05), "p25": pct(0.25), "p50": pct(0.50),
        "p75": pct(0.75), "p95": pct(0.95), "p99": pct(0.99),
        "distinct": len(set(round(v, 6) for v in vals)),
    }


# ------------------------------------------------------------------- baselines

def _weighted_from(grids):
    return [[[tables.TABLES[qid]["weight"] * cell for cell in row] for row in grid]
            for qid, grid in zip(population.SCORED_IDS, grids)]


def baseline_grids(kind, seed=7):
    """Same shape, same weights, different cells.

    `shuffled` keeps every value the tables use and only moves it, so it controls
    for the distribution of the numbers and isolates whether *where* they sit
    carries information. `alignment` is the rule somebody would write without
    thinking about it. `agreement` is a plain tally.
    """
    rng = random.Random(seed)
    out = []
    for qid in population.SCORED_IDS:
        grid = tables.TABLES[qid]["grid"]
        n = len(grid)
        if kind == "shuffled":
            vals = [grid[i][j] for i in range(n) for j in range(i, n)]
            rng.shuffle(vals)
            new = [[0.0] * n for _ in range(n)]
            k = 0
            for i in range(n):
                for j in range(i, n):
                    new[i][j] = new[j][i] = vals[k]
                    k += 1
        elif kind == "alignment":
            new = [[1.0 if i == j else (0.75 if abs(i - j) == 1 else 0.25)
                    for j in range(n)] for i in range(n)]
        elif kind == "agreement":
            new = [[1.0 if i == j else 0.0 for j in range(n)] for i in range(n)]
        else:
            raise KeyError(kind)
        out.append(new)
    return _weighted_from(out)


def score_with(weighted, a, b):
    total = 0.0
    for j in range(13):
        total += weighted[j][a.answers[j]][b.answers[j]]
    return total


def agreement_count(a, b):
    return sum(1 for j in range(13) if a.answers[j] == b.answers[j])


# ------------------------------------------------------- per-person separation

def _sample_people(people, graph, minimum, rng, size):
    pool = [p for p in people if len(graph[p.pid]) >= minimum]
    rng.shuffle(pool)
    return pool[:size]


def separation(people, graph, by_id, k=K_DEFAULT, size=250, seed=3):
    """Can the tables tell a person's own candidates apart?

    The pool that matters is not all pairs -- it is the set one person is actually
    ranked against, after the hard filters. A table can look varied across the whole
    city and still be flat inside everybody's own shortlist.
    """
    rng = random.Random(seed)
    chosen = _sample_people(people, graph, k * 4, rng, size)
    sds, margins, near10, near25, ties, pools, gaps = [], [], [], [], [], [], []
    for p in chosen:
        vals = [s for s, _ in graph[p.pid]]
        if len(vals) < k + 1:
            continue
        m, sd = st.fmean(vals), st.pstdev(vals)
        if sd == 0:
            continue
        cutoff = vals[k - 1]
        sds.append(sd)
        margins.append((cutoff - m) / sd)
        near10.append(sum(1 for v in vals if abs(v - cutoff) <= 0.10))
        near25.append(sum(1 for v in vals if abs(v - cutoff) <= 0.25))
        ties.append(sum(1 for v in vals if abs(v - cutoff) < 1e-9))
        pools.append(len(vals))
        gaps.append(vals[0] - vals[k - 1])

    def q(xs, p):
        xs = sorted(xs)
        return xs[min(len(xs) - 1, int(p * len(xs)))]

    return {
        "n": len(sds),
        "sd_min": min(sds), "sd_p10": q(sds, 0.10), "sd_med": q(sds, 0.50),
        "sd_p90": q(sds, 0.90), "sd_max": max(sds),
        "margin": st.fmean(margins),
        "near10": st.fmean(near10), "near25": st.fmean(near25),
        "ties": st.fmean(ties),
        "pool_med": q(pools, 0.50),
        "near25_frac": st.fmean([a / b for a, b in zip(near25, pools)]),
        "first_to_kth": st.fmean(gaps),
        "first_to_kth_sd": st.fmean(gaps) / st.fmean(sds),
    }


def _topk(p, graph, by_id, scorer, k):
    scored = [(scorer(p, by_id[o]), o) for _, o in graph[p.pid]]
    scored.sort(key=lambda t: -t[0])
    return set(o for _, o in scored[:k])


def baseline_overlap(people, graph, by_id, kind, k=K_DEFAULT, size=200, seed=4):
    """How much of your five survives swapping the tables for something else."""
    rng = random.Random(seed)
    weighted = baseline_grids(kind, seed=seed)
    chosen = _sample_people(people, graph, k * 4, rng, size)
    out = []
    for p in chosen:
        real = set(o for _, o in graph[p.pid][:k])
        alt = _topk(p, graph, by_id, lambda x, y: score_with(weighted, x, y), k)
        out.append(len(real & alt) / float(k))
    return st.fmean(out) if out else 0.0


def spearman_vs_agreement(people, graph, by_id, size=200, seed=5):
    """Is the table just counting matching answers in an expensive way?"""
    rng = random.Random(seed)
    chosen = _sample_people(people, graph, 20, rng, size)
    out = []
    for p in chosen:
        pairs = [(s, agreement_count(p, by_id[o])) for s, o in graph[p.pid]]
        if len(pairs) < 10:
            continue
        out.append(_spearman([a for a, _ in pairs], [b for _, b in pairs]))
    return st.fmean(out) if out else 0.0


def _rank(xs):
    order = sorted(range(len(xs)), key=lambda i: xs[i])
    ranks = [0.0] * len(xs)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and xs[order[j + 1]] == xs[order[i]]:
            j += 1
        avg = (i + j) / 2.0 + 1
        for k in range(i, j + 1):
            ranks[order[k]] = avg
        i = j + 1
    return ranks


def _spearman(xs, ys):
    rx, ry = _rank(xs), _rank(ys)
    mx, my = st.fmean(rx), st.fmean(ry)
    num = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    dx = math.sqrt(sum((a - mx) ** 2 for a in rx))
    dy = math.sqrt(sum((b - my) ** 2 for b in ry))
    return num / (dx * dy) if dx and dy else 0.0


def perturbation(people, graph, by_id, k=K_DEFAULT, size=200, seed=6):
    """Flip one answer. How much of the roster moves?

    Too little and the questionnaire is inert -- sixteen screens that change
    nothing. Too much and a single tap decides who somebody meets, which is worse.
    """
    rng = random.Random(seed)
    chosen = _sample_people(people, graph, k * 4, rng, size)
    out = []
    for p in chosen:
        j = rng.randrange(13)
        n = population.OPTIONS[population.SCORED_IDS[j]]
        alt = list(p.answers)
        alt[j] = (alt[j] + 1 + rng.randrange(n - 1)) % n
        original, p.answers = p.answers, tuple(alt)
        try:
            moved = _topk(p, graph, by_id, filters.score, k)
        finally:
            p.answers = original
        real = set(o for _, o in graph[p.pid][:k])
        out.append(len(real & moved) / float(k))
    return st.fmean(out) if out else 0.0


# ----------------------------------------------------------- delivered vs null

def null_graph(graph, seed):
    """The same candidates, ranked by noise instead of by compatibility."""
    rng = random.Random(seed + 999)
    out = {}
    for pid, edges in graph.items():
        shuffled = [(rng.random(), o) for _, o in edges]
        shuffled.sort(key=lambda t: -t[0])
        out[pid] = shuffled
    return out


def unconstrained_ceiling(graph, k=K_DEFAULT):
    """What everybody's top five would average if nobody else existed.

    Not achievable -- it ignores that the person you want has five slots of their
    own -- but it is the only honest denominator for the delivered gain. Without
    it, "half a standard deviation" sounds like a verdict rather than a fraction.
    """
    vals = []
    for pid, edges in graph.items():
        vals.extend(s for s, _ in edges[:k])
    return st.fmean(vals) if vals else 0.0


def delivered(result):
    """Real compatibility of the pairs actually handed out."""
    vals = result.pair_scores
    return {"n": len(vals), "mean": st.fmean(vals) if vals else 0.0,
            "sd": st.pstdev(vals) if len(vals) > 1 else 0.0}


# ------------------------------------------------------------------ starvation

CHECKS = (
    ("orientation", filters.orientation_ok),
    ("age", filters.age_ok),
    ("distance", filters.distance_ok),
    ("requirements", filters.requirements_ok),
)


def binding_constraint(person, people):
    """Which single rule, dropped on its own, would give this person candidates?

    The obvious attribution -- name the first filter that rejected the pair -- is
    worthless, because the filters run in a fixed order and whichever runs first
    collects the blame for everybody. This asks the question that actually has an
    answer: if exactly one rule were relaxed and the rest held, how many candidates
    would appear? The rule that unlocks the most is the one binding them.
    """
    out = {}
    for name, _ in CHECKS:
        count = 0
        for b in people:
            if b.pid == person.pid or b.paused:
                continue
            if all(fn(person, b) for other, fn in CHECKS if other != name):
                count += 1
        out[name] = count
    return out


def starvation(result, rejections, graph):
    """Who got nothing, how often, and which rule did it."""
    cfg = result.cfg
    people = result.people
    per_night = []
    for n in result.nights:
        active = [p for p in people if not p.paused and p.pid not in n["held"]]
        empty = [p for p in active if n["sizes"][p.pid] == 0]
        per_night.append({
            "night": n["night"],
            "pairs": len(n["pairs"]),
            "held": len(n["held"]),
            "active": len(active),
            "empty": len(empty),
            "full": sum(1 for p in active if n["sizes"][p.pid] >= p.capacity),
        })

    persistent = []
    for p in people:
        if p.paused:
            continue
        stt = result.states[p.pid]
        if stt.empty_nights >= 3:
            unlocked = binding_constraint(p, people)
            best = max(unlocked.items(), key=lambda kv: kv[1])
            have = len(graph[p.pid])
            persistent.append({
                "pid": p.pid, "nights": stt.empty_nights,
                "candidates": have,
                "reason": best[0] if best[1] > have else "pool",
                "unlocks": best[1],
                "city": p.place.city, "age": p.age, "gender": p.gender,
                "distance": p.distance, "met": len(stt.met),
            })
    persistent.sort(key=lambda r: (-r["nights"], r["candidates"]))

    met = sorted(len(result.states[p.pid].met) for p in people if not p.paused)

    def q(xs, f):
        return xs[min(len(xs) - 1, int(f * len(xs)))] if xs else 0

    return {
        "per_night": per_night,
        "persistent": persistent,
        "met_p10": q(met, 0.10), "met_med": q(met, 0.50), "met_p90": q(met, 0.90),
    }


def degree(result):
    """Delivered degree, and the invariant that mutual pairing is supposed to give."""
    worst = 0
    dupes = 0
    over = []
    for n in result.nights:
        seen = set()
        for a, b in n["pairs"]:
            key = (a, b) if a < b else (b, a)
            if key in seen:
                dupes += 1
            seen.add(key)
        for pid, f in n["filled"].items():
            worst = max(worst, f)
            if f > n["need"][pid]:
                over.append(pid)
    return {"max_filled": worst, "duplicates": dupes, "over_capacity": len(over)}
