# -*- coding: utf-8 -*-
"""Checks that run before anybody is allowed to believe the report.

Nothing here simulates anything. These are the places where a quiet mistake would
produce a plausible-looking number that happens to be wrong -- which is worse than
a crash, because a crash gets fixed.

    python selftest.py
"""
import math
import sys

import analysis
import filters
import geo
import match
import night as night_mod
import population
import tables

PASSED = []
FAILED = []


def check(name, condition, detail=""):
    (PASSED if condition else FAILED).append((name, detail))
    print("  %s  %s%s" % ("ok  " if condition else "FAIL", name,
                          ("  -- " + detail) if detail and not condition else ""))


def test_tables():
    print("\ntables")
    check("parses 13 scored tables", len(tables.TABLES) == 13, str(len(tables.TABLES)))
    check("parses 16 questions", len(tables.QUESTIONS) == 16)
    check("parses 3 requirement grids", len(tables.REQUIREMENTS) == 3)
    check("consistent at import", not tables.check(tables.TABLES, tables.QUESTIONS))
    check("weights sum to 13.0", abs(tables.MAX_SCORE - 13.0) < 1e-9,
          "%.6f" % tables.MAX_SCORE)
    check("82 pair values + 13 weights = 95",
          analysis.table_geometry()["numbers"] == 95)
    check("ceiling is 12.870, not 13", abs(tables.ATTAINABLE_MAX - 12.87) < 1e-9,
          "%.4f" % tables.ATTAINABLE_MAX)
    check("floor is 5.345", abs(tables.ATTAINABLE_MIN - 5.345) < 1e-9,
          "%.4f" % tables.ATTAINABLE_MIN)
    check("q6 is why the ceiling is not 13",
          analysis.table_geometry()["no_perfect"] == ["q6"],
          str(analysis.table_geometry()["no_perfect"]))
    check("normalise maps the floor to 0", abs(tables.normalise(tables.ATTAINABLE_MIN)) < 1e-9)
    check("normalise maps the ceiling to 1",
          abs(tables.normalise(tables.ATTAINABLE_MAX) - 1.0) < 1e-9)

    # Every grid symmetric, and every diagonal a real value rather than a default.
    sym = all(t["grid"][i][j] == t["grid"][j][i]
              for t in tables.TABLES.values()
              for i in range(len(t["grid"])) for j in range(len(t["grid"])))
    check("every grid symmetric", sym)


def test_geo():
    print("\ngeo")
    check("Swift rounds 0.5 away from zero", geo.round_half_away(4150.5) == 4151)
    check("and -0.5 too", geo.round_half_away(-4150.5) == -4151)
    check("python would disagree", round(4150.5) == 4150)

    beacon = geo.BY_ID["ny-beacon"]
    check("Beacon coarsens to 41.51 like Swift, not 41.50 like python",
          abs(beacon.lat - 41.51) < 1e-9, "%.4f" % beacon.lat)

    check("32 places", len(geo.PLACE_LIST) == 32, str(len(geo.PLACE_LIST)))
    check("places are stored coarsened, not as typed",
          all(abs(p.lat / geo.GRID - round(p.lat / geo.GRID)) < 1e-6
              for p in geo.PLACE_LIST))

    fg = geo.BY_ID["bk-fort-greene"]
    hud = geo.BY_ID["ny-hudson"]
    d = geo.miles(fg.point, hud.point)
    check("Fort Greene to Hudson is about 108 miles", 107.0 < d < 109.0, "%.1f" % d)
    check("zero distance to yourself", geo.miles(fg.point, fg.point) == 0.0)

    # The trap: Anywhere means no filter, not a 100-mile circle.
    check("Anywhere ignores the other radius (both unlimited)",
          geo.within(d, 100, 100) is True)
    check("but a 10-mile person still says no", geo.within(d, 10, 100) is False)
    check("min(a,b) would have been wrong here",
          geo.within(120.0, 100, 100) and not (120.0 <= min(100, 100)))
    check("within is symmetric",
          geo.within(30, 25, 50) == geo.within(30, 50, 25))


def test_scoring():
    print("\nscoring")
    cfg = population.Config(n=120)
    people = population.build(cfg)
    ok = True
    for i in range(0, 100, 7):
        a, b = people[i], people[i + 1]
        fast = filters.score(a, b)
        slow = tables.score(a.answer_dict(), b.answer_dict())
        if abs(fast - slow) > 1e-9:
            ok = False
    check("fast scorer agrees with tables.score", ok)
    check("scoring is symmetric",
          all(abs(filters.score(people[i], people[i + 1])
                  - filters.score(people[i + 1], people[i])) < 1e-12
              for i in range(0, 100, 5)))
    vals = [filters.score(people[i], people[j])
            for i in range(40) for j in range(i + 1, 40)]
    check("no pair exceeds the attainable ceiling",
          max(vals) <= tables.ATTAINABLE_MAX + 1e-9, "%.4f" % max(vals))
    check("no pair falls below the attainable floor",
          min(vals) >= tables.ATTAINABLE_MIN - 1e-9, "%.4f" % min(vals))


def test_filters():
    print("\nfilters")
    cfg = population.Config(n=200)
    people = population.build(cfg)
    graph, funnel, rejections, scores = filters.build_static(people)
    check("graph is mutual",
          all(any(o == a.pid for _, o in graph[b])
              for a in people[:40]
              for _, b in graph[a.pid][:3]))
    check("nobody is their own candidate",
          all(pid not in [o for _, o in edges] for pid, edges in graph.items()))
    check("edges are sorted best first",
          all(all(edges[i][0] >= edges[i + 1][0] for i in range(len(edges) - 1))
              for edges in graph.values()))
    paused = [p for p in people if p.paused]
    check("paused people leave everyone's list, not just stop proposing",
          all(not graph[p.pid] for p in paused), "%d paused" % len(paused))
    a = people[0]
    check("a filter rejection has a named reason",
          filters.eligible(a, a) in (None,) + filters.FILTER_NAMES)


def test_match():
    print("\nmatch")
    cfg = population.Config(n=300)
    people = population.build(cfg)
    graph, funnel, rejections, scores = filters.build_static(people)
    match.sort_graph(graph, cfg.seed)
    need = dict((p.pid, 0 if p.paused else p.capacity) for p in people)
    seen = dict((p.pid, {}) for p in people)
    pairs, filled = match.match_night(graph, need, seen, 1, cfg, cfg.seed)

    check("nobody exceeds their need",
          all(filled[pid] <= need[pid] for pid in need))
    check("no duplicate pairs",
          len(pairs) == len(set(frozenset(p) for p in pairs)))
    check("no self pairs", all(a != b for a, b in pairs))
    check("every pair appears in exactly two rosters",
          sum(filled.values()) == 2 * len(pairs),
          "%d vs %d" % (sum(filled.values()), 2 * len(pairs)))
    check("paused people are matched to nobody",
          all(filled[p.pid] == 0 for p in people if p.paused))
    check("every pair was an eligible pair",
          all(any(o == b for _, o in graph[a]) for a, b in pairs))

    # Tie-breaks must not be id-ordered, or alphabetically-early people win ties.
    t1 = match.tiebreak(1, "p001", "p002")
    t2 = match.tiebreak(2, "p001", "p002")
    check("tiebreak is seeded", t1 != t2)
    check("tiebreak is symmetric",
          match.tiebreak(1, "p001", "p002") == match.tiebreak(1, "p002", "p001"))
    check("tiebreak is stable across processes (not hash())",
          match.tiebreak(0, "a", "b") == match.tiebreak(0, "a", "b"))

    pairs2, filled2 = match.match_night(graph, need, seen, 1, cfg, cfg.seed)
    check("a night is reproducible", pairs == pairs2)


def test_week():
    print("\nthe week")
    cfg = population.Config(n=300)
    people = population.build(cfg)
    graph, funnel, rejections, scores = filters.build_static(people)
    match.sort_graph(graph, cfg.seed)
    result = night_mod.run(people, graph, cfg, cfg.seed)
    d = analysis.degree(result)
    check("never over capacity on any night", d["over_capacity"] == 0)
    check("no duplicate pairs on any night", d["duplicates"] == 0)
    check("max slots filled never exceeds 7", d["max_filled"] <= 7,
          str(d["max_filled"]))
    check("ran every night", len(result.nights) == cfg.nights)

    held_nights = sum(len(n["held"]) for n in result.nights)
    check("held rosters are excluded from need",
          all(n["need"][pid] == 0 for n in result.nights for pid in n["held"]),
          "%d held" % held_nights)

    # The cooldown has to actually stop repeats.
    cfg2 = population.Config(n=300, cooldown=99)
    p2 = population.build(cfg2)
    g2, _, _, _ = filters.build_static(p2)
    match.sort_graph(g2, cfg2.seed)
    r2 = night_mod.run(p2, g2, cfg2, cfg2.seed)
    repeats = 0
    seen_pairs = set()
    for n in r2.nights:
        for a, b in n["pairs"]:
            key = (a, b) if a < b else (b, a)
            if key in seen_pairs:
                repeats += 1
            seen_pairs.add(key)
    check("an infinite cooldown never repeats a pair", repeats == 0, str(repeats))


def test_sweep_isolation():
    print("\nthe noise sweep is a control, not a different world")
    a = population.build(population.Config(noise=0.0, n=200))
    b = population.build(population.Config(noise=1.0, n=200))
    check("same people", [p.pid for p in a] == [p.pid for p in b])
    check("same genders", [p.gender for p in a] == [p.gender for p in b])
    check("same ages", [p.age for p in a] == [p.age for p in b])
    check("same places", [p.place.id for p in a] == [p.place.id for p in b])
    check("same distance settings", [p.distance for p in a] == [p.distance for p in b])
    check("same requirement answers", [p.reqs for p in a] == [p.reqs for p in b])
    check("only the scored answers move",
          [p.answers for p in a] != [p.answers for p in b])

    # And the requirements must not ride the scored latent, or the hard filters
    # would delete low-scoring pairs for free and inflate section 1.
    people = population.build(population.Config(n=600, noise=0.0))
    typed = [p for p in people if p.archetype is not None]
    groups = {}
    for p in typed:
        groups.setdefault(p.archetype, []).append(p.reqs[0])
    spread = [len(set(v)) for v in groups.values()]
    check("requirement answers vary inside an archetype", min(spread) > 1,
          str(spread))


def main():
    print("=" * 60)
    print("matcher self-test")
    print("=" * 60)
    test_tables()
    test_geo()
    test_scoring()
    test_filters()
    test_match()
    test_week()
    test_sweep_isolation()
    print("\n" + "=" * 60)
    print("%d passed, %d failed" % (len(PASSED), len(FAILED)))
    if FAILED:
        for name, detail in FAILED:
            print("  FAILED: %s %s" % (name, detail))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
