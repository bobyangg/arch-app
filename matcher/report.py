# -*- coding: utf-8 -*-
"""Printing the run. No analysis here, and no analysis in the other file prints."""
import os
import subprocess
import sys

import analysis
import filters
import match
import night as night_mod
import population
import tables

WIDTH = 78


def rule(char="-"):
    return char * WIDTH


def head(title):
    return "\n" + rule("=") + "\n" + title + "\n" + rule("=")


def sub(title):
    return "\n" + title + "\n" + rule()


def git_sha(path):
    try:
        out = subprocess.run(
            ["git", "log", "-1", "--format=%h", "--", path],
            capture_output=True, text=True, cwd=tables.ROOT,
        )
        return out.stdout.strip() or "unknown"
    except Exception:
        return "unknown"


def verdict(value, good, bad, higher_is_better=True):
    """A word next to a number, so the reader is not left to remember thresholds."""
    if higher_is_better:
        if value >= good:
            return "PASS"
        return "FAIL" if value <= bad else "weak"
    if value <= good:
        return "PASS"
    return "FAIL" if value >= bad else "weak"


def header(cfg, out):
    out(head("Arch matcher -- do the 95 numbers work?"))
    out("Compatibility.swift at %s" % git_sha(os.path.join("Arch", "Mock", "Compatibility.swift")))
    out("")
    items = [(k, v) for k, v in cfg.items()]
    for i in range(0, len(items), 3):
        out("  " + "".join("%-24s" % ("%s=%s" % (k, v)) for k, v in items[i:i + 3]))


def section0(out):
    g = analysis.table_geometry()
    out(head("0. The tables themselves"))
    out("  parsed              %d tables, %d requirement grids, %d cells"
        % (len(tables.TABLES), len(tables.REQUIREMENTS), g["cells"]))
    out("  hand-written        %d pair values + %d weights = %d numbers"
        % (g["unique"], len(tables.TABLES), g["numbers"]))
    out("  consistency         square, symmetric, in range -- checked at import")
    out("  weights sum to      %.3f" % g["weights_sum"])
    out("  attainable ceiling  %.3f   <-- not %.3f."
        % (g["attainable_max"], g["weights_sum"]))
    out("                      %s has no 1.00 cell, so every pair loses %.2f."
        % (", ".join(g["no_perfect"]), g["weights_sum"] - g["attainable_max"]))
    out("  attainable floor    %.3f" % g["attainable_min"])
    out("  working range       %.3f points" % g["span"])
    out("")
    out("  Anything reported as a percentage of 13 would squash that range into a")
    out("  band around 77% and make good tables look like noise.")


def section1(people, graph, by_id, cfg, result, null_result, out):
    out(head("1. Do the tables discriminate?"))

    u = analysis.uniform_moments()
    d = analysis.score_distribution(people)
    g = analysis.table_geometry()

    out(sub("1a. The spread of a pair score"))
    out("  if everyone answered at random   mean %.3f  sd %.3f" % (u["mean"], u["sd"]))
    out("  in this population               mean %.3f  sd %.3f" % (d["mean"], d["sd"]))
    out("  percentiles   p1 %.2f  p5 %.2f  p25 %.2f  p50 %.2f  p75 %.2f  p95 %.2f  p99 %.2f"
        % (d["p1"], d["p5"], d["p25"], d["p50"], d["p75"], d["p95"], d["p99"]))
    out("  distinct values seen             %d" % d["distinct"])
    out("  sd as a share of the range       %.1f%%" % (100.0 * d["sd"] / g["span"]))

    out(sub("1b. Which questions actually move the number"))
    out("  Weight and influence are not the same thing: a heavily weighted question")
    out("  with a flat grid changes nothing. Share of variance, under random answers:")
    out("")
    out("      q     weight   share   ")
    for qid, w, share in u["shares"]:
        bar = "#" * int(round(share * 100))
        flag = "   <-- nearly flat" if share < 0.02 else ""
        out("      %-4s  %.1f    %5.1f%%  %s%s" % (qid, w, share * 100, bar, flag))

    sep = analysis.separation(people, graph, by_id)
    out(sub("1c. Can the tables tell one person's own candidates apart?"))
    out("  (the only pool that matters -- their shortlist after the hard filters)")
    out("  candidate-score sd   min %.3f  p10 %.3f  median %.3f  p90 %.3f  max %.3f"
        % (sep["sd_min"], sep["sd_p10"], sep["sd_med"], sep["sd_p90"], sep["sd_max"]))
    out("  median pool size     %d people" % sep["pool_med"])
    out("  verdict              %s  (good >= 0.60, bad < 0.35)"
        % verdict(sep["sd_med"], 0.60, 0.35))

    out(sub("1d. Is the fifth pick meaningfully above the pool?"))
    out("  selection margin     %.2f sd above the candidate mean" % sep["margin"])
    out("  verdict              %s  (good >= 1.5, bad < 0.8)"
        % verdict(sep["margin"], 1.5, 0.8))
    out("  within 0.10 of the cutoff   %.1f people" % sep["near10"])
    out("  within 0.25 of the cutoff   %.1f people (%.0f%% of the pool)"
        % (sep["near25"], 100.0 * sep["near25_frac"]))
    out("  exact ties at the cutoff    %.2f" % sep["ties"])
    out("  1st pick beats 5th by       %.2f points (%.2f pool sd)"
        % (sep["first_to_kth"], sep["first_to_kth_sd"]))

    out(sub("1e. Against other tables of the same shape -- the decisive test"))
    shuffled = analysis.baseline_overlap(people, graph, by_id, "shuffled")
    alignment = analysis.baseline_overlap(people, graph, by_id, "alignment")
    agreement = analysis.baseline_overlap(people, graph, by_id, "agreement")
    spear = analysis.spearman_vs_agreement(people, graph, by_id)
    perturb = analysis.perturbation(people, graph, by_id)
    out("  How much of somebody's five survives replacing the tables with:")
    out("")
    out("    same values, shuffled cells   %.2f   %s  (good <= 0.25, bad >= 0.50)"
        % (shuffled, verdict(shuffled, 0.25, 0.50, False)))
    out("    a mechanical alignment rule   %.2f   %s  (good <= 0.65, bad >= 0.90)"
        % (alignment, verdict(alignment, 0.65, 0.90, False)))
    out("    a plain count of agreement    %.2f" % agreement)
    out("")
    out("  Spearman vs agreement count     %.2f   %s  (good <= 0.80, bad >= 0.95)"
        % (spear, verdict(spear, 0.80, 0.95, False)))
    out("  Roster kept after flipping one answer  %.2f   %s  (good 0.55-0.85)"
        % (perturb, "PASS" if 0.55 <= perturb <= 0.85 else "check"))

    out(sub("1f. Delivered -- the real matcher against the same matcher on noise"))
    ceiling = analysis.unconstrained_ceiling(graph)
    real = analysis.delivered(result)
    null = analysis.delivered(null_result)
    unit = sep["sd_med"] or 1.0
    gap = (real["mean"] - null["mean"]) / unit
    out("  real tables      %d pairs, mean compatibility %.3f (sd %.3f)"
        % (real["n"], real["mean"], real["sd"]))
    out("  ranked by noise  %d pairs, mean compatibility %.3f (sd %.3f)"
        % (null["n"], null["mean"], null["sd"]))
    out("  gain             %+.3f points = %.2f pool sd   %s  (good >= 1.2, bad < 0.5)"
        % (real["mean"] - null["mean"], gap, verdict(gap, 1.2, 0.5)))
    out("")
    out("  For scale: picking everybody's unconstrained best five would average")
    out("  %.3f. The mutual cap and the cooldown eat the rest, so the matcher"
        % ceiling)
    out("  captures %.0f%% of the lift the tables actually offer."
        % (100.0 * (real["mean"] - null["mean"]) / max(1e-9, ceiling - null["mean"])))
    out("")
    out("  This is the only line in the section that is not circular: the matcher")
    out("  maximises score, so it would report good scores whatever the tables said.")
    return {"shuffled": shuffled, "alignment": alignment, "spearman": spear,
            "perturb": perturb, "margin": sep["margin"], "sd_med": sep["sd_med"],
            "gain_sd": gap}


def section2(result, rejections, graph, out):
    s = analysis.starvation(result, rejections, graph)
    out(head("2. Who starves?"))
    out("  night   pairs   held   active   empty   full rosters")
    for r in s["per_night"]:
        out("    %d    %5d   %4d   %6d   %5d   %5d"
            % (r["night"], r["pairs"], r["held"], r["active"], r["empty"], r["full"]))
    out("")
    out("  unique people met across the week   p10 %d   median %d   p90 %d"
        % (s["met_p10"], s["met_med"], s["met_p90"]))
    out("")
    persistent = s["persistent"]
    out("  Empty on 3 or more of %d nights: %d people" % (len(s["per_night"]), len(persistent)))
    if persistent:
        from collections import Counter
        out("")
        out("  which single rule, relaxed on its own, would unstick them:")
        for reason, count in Counter(r["reason"] for r in persistent).most_common():
            out("      %-14s %d" % (reason, count))
        out("  by where they live:")
        for city, count in Counter(r["city"] for r in persistent).most_common():
            out("      %-14s %d" % (city, count))
        out("  by their distance setting:")
        for dist, count in sorted(Counter(r["distance"] for r in persistent).items()):
            label = "Anywhere" if dist >= 100 else "%d miles" % dist
            out("      %-14s %d" % (label, count))
        out("")
        out("  worst affected:")
        out("      pid     nights  candidates  met  binding rule   would give  where")
        for r in persistent[:12]:
            out("      %-7s %4d    %8d  %5d  %-13s %8d    %s"
                % (r["pid"], r["nights"], r["candidates"], r["met"],
                   r["reason"], r["unlocks"], r["city"]))
    return s


def section3(result, graph, out):
    d = analysis.degree(result)
    need = dict((p.pid, p.capacity) for p in result.people)
    demand = match.shadow_demand(graph, need)
    vals = sorted(demand.values())

    def q(f):
        return vals[min(len(vals) - 1, int(f * len(vals)))]

    out(head("3. What the mutual cap costs"))
    out("  invariants   max slots filled %d   over capacity %d   duplicate pairs %d"
        % (d["max_filled"], d["over_capacity"], d["duplicates"]))
    out("               (the cap holds by construction -- pairing spends both slots)")
    out("")
    out("  The real question is how much work it is doing. Shadow demand is how many")
    out("  people would hold you in their top five with no constraints at all:")
    out("")
    out("      median %d   p90 %d   p95 %d   max %d   (capacity 5)"
        % (q(0.50), q(0.90), q(0.95), vals[-1]))
    out("      wanted by nobody: %d people" % sum(1 for v in vals if v == 0))
    ratio = q(0.95) / 5.0
    out("      p95 is %.1fx capacity   %s  (good <= 3x)"
        % (ratio, "PASS" if ratio <= 3 else "crowded"))


def section4(people, graph, out):
    counts = filters.cumulative_funnel(people)
    out(head("4. Do candidate sets survive the filters?"))
    total = counts["all pairs"]
    out("  every possible pair                    %8d   100.0%%" % total)
    previous = total
    for name in filters.FILTER_NAMES:
        c = counts[name]
        out("  after %-32s %8d   %5.1f%%   (-%.1f%%)"
            % (name, c, 100.0 * c / total, 100.0 * (previous - c) / total))
        previous = c
    out("")
    sizes = sorted(len(graph[p.pid]) for p in people if not p.paused)

    def q(f):
        return sizes[min(len(sizes) - 1, int(f * len(sizes)))]

    out("  candidates per person   min %d   p10 %d   p25 %d   median %d   p90 %d"
        % (sizes[0], q(0.10), q(0.25), q(0.50), q(0.90)))
    out("  below 5 (one roster)    %d people" % sum(1 for s in sizes if s < 5))
    out("  below 35 (a full week)  %d people" % sum(1 for s in sizes if s < 35))
    out("")
    out("  Candidate sets scale with the size of the city. At n=%d this is a small"
        % len(people))
    out("  town; the shape of the funnel is the transferable finding, not the counts.")


def requirement_rates(people, out):
    from collections import Counter
    out("")
    out("  the three requirement questions, pass rate over random pairs:")
    grids = [tables.REQUIREMENTS[q] for q in population.REQ_IDS]
    import random as _r
    rng = _r.Random(9)
    for j, qid in enumerate(population.REQ_IDS):
        ok = 0
        for _ in range(20000):
            a = people[rng.randrange(len(people))]
            b = people[rng.randrange(len(people))]
            if grids[j][a.reqs[j]][b.reqs[j]]:
                ok += 1
        out("      %-4s  %.1f%%" % (qid, 100.0 * ok / 20000))
