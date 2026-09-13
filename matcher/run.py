# -*- coding: utf-8 -*-
"""Run the simulation and print the report.

    python run.py                      the full report
    python run.py --sweep noise        the control that decides the headline
    python run.py --sweep cooldown     is the starving cohort the cooldown's fault?
"""
import argparse
import sys

import analysis
import filters
import match
import night as night_mod
import population
import report


def build_world(cfg, seed=None):
    """Population, candidate graph, both nightly runs. One seed, one world."""
    seed = cfg.seed if seed is None else seed
    people = population.build(cfg, seed=seed)
    graph, funnel, rejections, scores = filters.build_static(people)
    match.sort_graph(graph, seed)
    by_id = dict((p.pid, p) for p in people)

    result = night_mod.run(people, graph, cfg, seed)
    # Same population, same filters, same capacities, same behaviour stream --
    # only the ranking is replaced. Common random numbers, so the difference
    # between the two is the tables and nothing else.
    null = night_mod.run(people, graph, cfg, seed,
                         scorer=analysis.null_graph(graph, seed))
    return people, graph, by_id, rejections, result, null


def full_report(cfg, out):
    people, graph, by_id, rejections, result, null = build_world(cfg)
    report.header(cfg, out)
    report.section0(out)
    summary = report.section1(people, graph, by_id, cfg, result, null, out)
    report.section2(result, rejections, graph, out)
    report.section3(result, graph, out)
    report.section4(people, graph, out)
    report.requirement_rates(people, out)
    return summary


def sweep_noise(cfg, out, seeds):
    out(report.head("5. The control: does the headline survive noisier answers?"))
    out("  Crisp archetypes would make any scoring rule look good -- the pool would be")
    out("  full of near clones. noise=1.00 is answers drawn at random, with no types")
    out("  at all. The claim in section 1 only stands if it holds at noise >= 0.30.")
    out("")
    out("  noise   cand sd   margin   vs shuffled   vs alignment   spearman   gain(sd)")
    for noise in (0.0, 0.15, 0.30, 0.50, 1.0):
        rows = []
        for s in seeds:
            c = population.Config(**dict(cfg.__dict__, noise=noise))
            people, graph, by_id, rej, result, null = build_world(c, seed=s)
            sep = analysis.separation(people, graph, by_id)
            sh = analysis.baseline_overlap(people, graph, by_id, "shuffled")
            al = analysis.baseline_overlap(people, graph, by_id, "alignment")
            sp = analysis.spearman_vs_agreement(people, graph, by_id)
            r, n = analysis.delivered(result), analysis.delivered(null)
            gain = (r["mean"] - n["mean"]) / (sep["sd_med"] or 1.0)
            rows.append((sep["sd_med"], sep["margin"], sh, al, sp, gain))
        avg = [sum(r[i] for r in rows) / len(rows) for i in range(6)]
        out("  %5.2f   %7.3f   %6.2f   %11.2f   %12.2f   %8.2f   %8.2f"
            % (noise, avg[0], avg[1], avg[2], avg[3], avg[4], avg[5]))
    out("")
    out("  (mean of %d seeds per row)" % len(seeds))


def sweep_cooldown(cfg, out, seeds):
    out(report.head("5. The control: is the starving cohort the cooldown's fault?"))
    out('  "Never show the same person twice" is a guarantee that runs out of people.')
    out("  Nights is %d, so a cooldown of %d means nobody repeats all week." % (cfg.nights, cfg.nights))
    out("")
    out("  cooldown   pairs/night   empty night 7   persistent zero   met (median)")
    for cd in (0, 3, 7, 99):
        rows = []
        for s in seeds:
            c = population.Config(**dict(cfg.__dict__, cooldown=cd))
            people, graph, by_id, rej, result, null = build_world(c, seed=s)
            st = analysis.starvation(result, rej, graph)
            last = st["per_night"][-1]
            active = float(last["active"]) or 1.0
            avg_pairs = sum(r["pairs"] for r in st["per_night"]) / float(len(st["per_night"]))
            rows.append((avg_pairs, 100.0 * last["empty"] / active,
                         100.0 * len(st["persistent"]) / active, st["met_med"]))
        avg = [sum(r[i] for r in rows) / len(rows) for i in range(4)]
        label = "none" if cd == 0 else ("never" if cd > cfg.nights else str(cd))
        out("  %-9s  %11.0f   %12.1f%%   %14.1f%%   %12.0f"
            % (label, avg[0], avg[1], avg[2], avg[3]))
    out("")
    out("  The trade is real and it is the product decision, not a bug: the cooldown")
    out("  is what stops the same faces recurring, and it is also what strands the")
    out("  people whose candidate list is short. Compare the last two columns.")


def sweep_size(cfg, out, seeds):
    out(report.head("5. The control: how much of this is just a small city?"))
    out("  Candidate sets scale with the population. A cohort that starves at n=400")
    out("  and not at n=2400 is a launch problem, not a design problem.")
    out("")
    out("     n     median candidates   p10    empty night 7   persistent zero")
    for n in (300, 600, 1200, 2400):
        rows = []
        for s in seeds[:2]:
            c = population.Config(**dict(cfg.__dict__, n=n))
            people, graph, by_id, rej, result, null = build_world(c, seed=s)
            sizes = sorted(len(graph[p.pid]) for p in people if not p.paused)
            stv = analysis.starvation(result, rej, graph)
            active = float(len(sizes))
            rows.append((sizes[len(sizes) // 2], sizes[len(sizes) // 10],
                         100.0 * stv["per_night"][-1]["empty"] / active,
                         100.0 * len(stv["persistent"]) / active))
        avg = [sum(r[i] for r in rows) / len(rows) for i in range(4)]
        out("  %5d   %17.0f   %3.0f   %12.1f%%   %14.1f%%"
            % (n, avg[0], avg[1], avg[2], avg[3]))
    out("")
    out("  Counts would have risen down this column and said the opposite. As a share")
    out("  of the city, a bigger pool is the single most effective fix available.")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Arch matcher simulation")
    ap.add_argument("--seed", type=int, default=20260912)
    ap.add_argument("--n", type=int, default=600)
    ap.add_argument("--nights", type=int, default=7)
    ap.add_argument("--noise", type=float, default=0.30)
    ap.add_argument("--archetypes", type=int, default=6)
    ap.add_argument("--cooldown", type=int, default=7)
    ap.add_argument("--age-asymmetry", action="store_true")
    ap.add_argument("--sweep", choices=("noise", "cooldown", "size"))
    ap.add_argument("--seeds", type=int, default=3)
    ap.add_argument("--out", default=None, help="also write the report here")
    args = ap.parse_args(argv)

    cfg = population.Config(
        seed=args.seed, n=args.n, nights=args.nights, noise=args.noise,
        archetypes=args.archetypes, cooldown=args.cooldown,
        age_asymmetry=args.age_asymmetry,
    )

    lines = []

    def out(text=""):
        lines.append(text)
        print(text)

    seeds = [args.seed + i * 1000 for i in range(args.seeds)]
    if args.sweep == "noise":
        report.header(cfg, out)
        sweep_noise(cfg, out, seeds)
    elif args.sweep == "cooldown":
        report.header(cfg, out)
        sweep_cooldown(cfg, out, seeds)
    elif args.sweep == "size":
        report.header(cfg, out)
        sweep_size(cfg, out, seeds)
    else:
        full_report(cfg, out)

    if args.out:
        with open(args.out, "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
