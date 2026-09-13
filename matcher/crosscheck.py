# -*- coding: utf-8 -*-
"""Prove the SQL matcher and this simulation agree, pair for pair.

`backend/006_matcher.sql` is a port of `match.py`. A port is a second
implementation, and two implementations of an algorithm this fiddly will differ
somewhere unless something forces them not to. This is that something.

It emits one SQL script that:

  1. seeds a population generated here into the real tables,
  2. runs the database matcher over it at a fixed night and seed,
  3. compares the pairs it produced against the pairs *this* program produced,
     which are embedded in the script as a literal list,
  4. prints a verdict,
  5. rolls the whole thing back.

**Set equality, not score comparison.** `pairings.score` is `real`, so a score
read back will not round-trip a float64 and a comparison on it would pass or fail
for reasons that have nothing to do with the matcher.

    python crosscheck.py > check.sql     then run check.sql against the database

Two things make exact agreement achievable at all, and without either of them this
comparison could only ever be approximate:

  * scores are integer thousandths on both sides, so no summation order matters,
  * the tiebreak is sha256 over the same `seed|lo|hi` string on both sides.
"""
import sys
import uuid

import filters
import match
import population as pop

#: Small on purpose. The point is exactness, not scale -- and every pair has to be
#: written into the script as a literal for the database to compare against.
N = 60
NIGHT = "2026-06-15"
SEED = 424242

GENDER_SQL = {"man": "man", "woman": "woman", "nonBinary": "non_binary"}


def account_id(index):
    """A stable uuid per person, so a re-run seeds the same ids.

    The ids matter beyond identity: the tiebreak hashes `seed|lo|hi`, so both
    sides must agree on the strings *and* on which of a pair is `lo`. Postgres
    orders uuids by their sixteen bytes and Python orders these by text, which
    agree for canonical lowercase hex -- the hyphens sit at the same offsets in
    every id and the hex digits sort in value order.
    """
    return str(uuid.UUID(int=(0xA5C0 << 112) | index))


def build():
    cfg = pop.Config(n=N, seed=20260615, cooldown=0)
    people = pop.build(cfg)

    # Blocks are recorded against the generator's own ids ("p007"), so they must be
    # translated, not filtered. Dropping the ones that "do not match" silently
    # removes every block in the population and the block filter is never
    # exercised at all -- which is what the first version of this did.
    remap = {person.pid: account_id(i) for i, person in enumerate(people)}
    for person in people:
        person.blocks = set(remap[b] for b in person.blocks if b in remap)
    for i, person in enumerate(people):
        person.pid = account_id(i)
    return cfg, people


def expected_pairs(cfg, people):
    """What this program says tonight should be."""
    graph, _funnel, _rejections, _scores = filters.build_static(people)
    match.sort_graph(graph, SEED)
    need = dict((p.pid, 0 if p.paused else p.capacity) for p in people)
    seen = dict((p.pid, {}) for p in people)
    pairs, _filled = match.match_night(graph, need, seen, 1, cfg, SEED)
    return sorted(tuple(sorted(pair)) for pair in pairs)


def seed_sql(people):
    out = []
    add = out.append

    # These two carry no per-person data beyond the id, so they are generated in
    # the database rather than written out a row at a time. The id shape has to
    # match `account_id()` exactly -- it is what the tiebreak hashes.
    add("create temp table cc_ids as")
    add("select i, ('a5c00000-0000-0000-0000-' || lpad(to_hex(i), 12, '0'))::uuid as id")
    add("from generate_series(0, %d) i;" % (len(people) - 1))

    add("\ninsert into auth.users (id, aud, role, email, created_at, updated_at)")
    add("select id, 'authenticated', 'authenticated',")
    add("       'x' || lpad(i::text, 3, '0') || '@crosscheck.invalid', now(), now()")
    add("from cc_ids;")

    add("\ninsert into accounts (id, apple_user_id)")
    add("select id, 'cc-' || lpad(i::text, 3, '0') from cc_ids;")

    # `extract(year from age(birthdate))` must give back exactly the age this
    # program used, so the birthdate is a day past the anniversary rather than on
    # it -- on it, a leap year can round the wrong way.
    add("\ninsert into profiles (account_id, name, birthdate, gender, place_id,"
        " coarse_lat, coarse_lon) values")
    add(",\n".join(
        "  ('%s','P%03d', current_date - interval '%d years' - interval '1 day',"
        " '%s', '%s', %.2f, %.2f)"
        % (p.pid, i, p.age, GENDER_SQL[p.gender], p.place.id, p.lat, p.lon)
        for i, p in enumerate(people)) + ";")

    add("\ninsert into discovery_settings (account_id, seeking, distance_miles,"
        " min_age, max_age, paused) values")
    add(",\n".join(
        "  ('%s', array[%s]::gender[], %d, %d, %d, %s)"
        % (p.pid,
           ",".join("'%s'" % GENDER_SQL[g] for g in sorted(p.seeking)),
           p.distance, p.min_age, p.max_age, "true" if p.paused else "false")
        for p in people) + ";")

    # Capacity is 7 with an unexpired subscription and 5 without, so premium has to
    # be seeded as the row the matcher actually reads rather than asserted.
    premium = [p for p in people if p.premium]
    if premium:
        add("\ninsert into subscriptions (account_id, apple_original_txn, expires_at) values")
        add(",\n".join(
            "  ('%s','cc-txn-%s', now() + interval '30 days')" % (p.pid, p.pid[-6:])
            for p in premium) + ";")

    # One row per person carrying all sixteen answers, unrolled on the way in.
    # Sixteen separate rows each would be 960 lines for sixty people, and the
    # array form is also the order the matcher reads them in.
    add("\ninsert into questionnaire_answers (account_id, question_id, option_index)")
    add("select p.id, 'q' || k, p.a[k]")
    add("from (values")
    add(",\n".join(
        "  ('%s'::uuid, array[%s])"
        % (p.pid, ",".join(str(v) for v in list(p.answers) + list(p.reqs)))
        for p in people))
    add(") as p(id, a), lateral generate_subscripts(p.a, 1) as k;")

    blocks = [(p.pid, b) for p in people for b in sorted(p.blocks) if b != p.pid]
    if blocks:
        add("\ninsert into blocks (blocker_id, blocked_id) values")
        add(",\n".join("  ('%s','%s')" % pair for pair in blocks) + ";")

    return "\n".join(out)


def main():
    cfg, people = build()
    pairs = expected_pairs(cfg, people)

    print("-- Cross-check: does the SQL matcher agree with matcher/match.py?")
    print("--")
    print("-- Generated by matcher/crosscheck.py. Seeds %d people, runs the database" % N)
    print("-- matcher over them at a fixed night and seed, and compares the result")
    print("-- against the pairs this program produced for the same population.")
    print("--")
    print("-- Ends in ROLLBACK: nothing it creates survives.")
    print()
    print("begin;")
    print()
    print(seed_sql(people))
    print()
    print("-- Run the three stages directly rather than run_nightly_match(), so the")
    print("-- seed is the one this program used rather than one derived from today.")
    print("select private.match_population('%s'::date) as people;" % NIGHT)
    print("select private.match_build_edges('%s'::date, %d) as edges;" % (NIGHT, SEED))
    print("select private.match_rounds('%s'::date, %d) as pairs_made;" % (NIGHT, SEED))
    print()
    print("-- What this program expects, as a literal.")
    print("create temp table expected (lo uuid, hi uuid) on commit drop;")
    if pairs:
        print("insert into expected (lo, hi) values")
        print(",\n".join("  ('%s','%s')" % pair for pair in pairs) + ";")
    print()
    print("""-- The database's own answer, read out of match_state rather than out of
-- `pairings`, so the comparison does not depend on the write-back step.
create temp table produced (lo uuid, hi uuid) on commit drop;
insert into produced (lo, hi)
select least(s.account_id, t.other), greatest(s.account_id, t.other)
  from match_state s
  cross join lateral unnest(s.taken) as t(other)
 where s.night = '%s'::date and s.account_id < t.other;

select
    (select count(*) from expected) as expected_pairs,
    (select count(*) from produced) as produced_pairs,
    (select count(*) from (select * from expected except select * from produced) x)
        as only_in_python,
    (select count(*) from (select * from produced except select * from expected) x)
        as only_in_sql,
    case when not exists (select * from expected except select * from produced)
          and not exists (select * from produced except select * from expected)
         then 'MATCH -- the port agrees with the simulation, pair for pair'
         else '>>> DIVERGED <<<' end as verdict;

-- If it diverged, this says where.
select 'only in python' as side, lo, hi from (select * from expected except select * from produced) a
union all
select 'only in sql', lo, hi from (select * from produced except select * from expected) b
limit 40;

rollback;""" % NIGHT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
