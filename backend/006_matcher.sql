-- Arch: the nightly matcher.
--
-- A port of `matcher/match.py`, which is the verified one. That program exists so
-- this one can be checked against it rather than trusted, and `matcher/crosscheck.py`
-- asserts the two produce the identical set of pairs on the identical population.
--
-- **Not Gale-Shapley.** That solves a bipartite one-to-one problem with two sides.
-- This is one side, many-to-many, on a general graph -- the stable roommates
-- problem, which can simply have no stable solution. So it is rounds of proposals:
-- each round, every unfilled person takes their best still-available candidate,
-- scarcest first.
--
-- **Scores are integer thousandths.** Floating-point addition is not associative
-- and a score is a sum of thirteen terms; measured, 54% of scores differ between
-- forward and reverse summation of the identical terms, and because ties are broken
-- by a hash a one-ULP difference flips who somebody takes. End to end that moved
-- half the delivered pairs, with both outputs looking like plausible rosters.
--
-- Everything lives in `private`, so PostgREST has no route to any of it. That
-- lesson was paid for once already -- see the header of 002_policies.sql.

-- ------------------------------------------------------------------ the log
--
-- Permanent, and doing three jobs: the primary key is the idempotency guard, the
-- timings are the only way to know the job is healthy, and held/empty are the same
-- starvation numbers `matcher/analysis.py` reports, so the simulation and
-- production stay comparable.
create table if not exists match_runs (
    night       date primary key,
    seed        bigint not null,
    started_at  timestamptz not null default now(),
    finished_at timestamptz,
    people      integer,
    edges       integer,
    pairs       integer,
    -- Counted separately from `empty`. A held roster is the hold policy working;
    -- folding it into starvation would make a product decision look like a bug.
    held        integer,
    empty       integer,
    note        text
);

alter table match_runs enable row level security;

-- Working tables. `unlogged` because they are rebuilt every night and a crash
-- mid-run should discard them; kept rather than `temp` so a run can be read
-- afterwards when the numbers look wrong.
create unlogged table if not exists match_people (
    night       date not null,
    account_id  uuid not null,
    gender      gender not null,
    seeking     gender[] not null,
    age         smallint not null,
    min_age     smallint not null,
    max_age     smallint not null,
    lat         numeric(8,2) not null,
    lon         numeric(9,2) not null,
    radius      smallint not null,
    capacity    smallint not null,
    retained    smallint not null,
    need        smallint not null,
    held        boolean not null default false,
    ans         smallint[] not null,
    req         smallint[] not null,
    primary key (night, account_id)
);

create unlogged table if not exists match_edges (
    night      date not null,
    account_id uuid not null,
    other_id   uuid not null,
    milli      integer not null,
    tie        bytea not null,
    rank       integer not null,
    primary key (night, account_id, other_id)
);
create index if not exists match_edges_rank_idx on match_edges (night, account_id, rank);

create unlogged table if not exists match_state (
    night      date not null,
    account_id uuid not null,
    need       smallint not null,
    filled     smallint not null default 0,
    taken      uuid[] not null default '{}',
    primary key (night, account_id)
);

alter table match_people enable row level security;
alter table match_edges enable row level security;
alter table match_state enable row level security;


-- ------------------------------------------------------------------ the tunables
--
-- Functions rather than constants so the cross-check can read the same values the
-- matcher uses, instead of a copy that drifts.

create or replace function private.match_cooldown()
returns integer language sql immutable as $$ select 7 $$;

-- Great-circle miles. Earth radius and the atan2 form both match
-- `matcher/geo.py`, which matters because the cross-check compares pair sets and a
-- disagreement at a radius boundary would look like an algorithm difference.
create or replace function private.arch_miles(
    lat1 numeric, lon1 numeric, lat2 numeric, lon2 numeric)
returns double precision language sql immutable as $$
    select 2 * 3958.8 * atan2(
        sqrt(h.v),
        sqrt(1 - h.v)
    )
    from (select
        sin(radians((lat2 - lat1)::double precision) / 2) ^ 2
        + cos(radians(lat1::double precision)) * cos(radians(lat2::double precision))
          * sin(radians((lon2 - lon1)::double precision) / 2) ^ 2
    ) as h(v)
$$;


-- ------------------------------------------------------------- who is playing

create or replace function private.match_population(_night date)
returns integer language plpgsql security definer set search_path = public as $$
declare
    n integer;
begin
    delete from match_people where night = _night;

    insert into match_people (
        night, account_id, gender, seeking, age, min_age, max_age,
        lat, lon, radius, capacity, retained, need, held, ans, req)
    select
        _night,
        p.account_id,
        p.gender,
        d.seeking,
        extract(year from age(p.birthdate))::smallint,
        d.min_age,
        d.max_age,
        p.coarse_lat,
        p.coarse_lon,
        d.distance_miles,
        cap.capacity,
        cap.retained,
        case when d.paused or cap.is_held then 0::smallint
             else greatest(0, cap.capacity - cap.retained)::smallint end,
        cap.is_held,
        a.ans,
        a.req
    from profiles p
    join accounts acc on acc.id = p.account_id and acc.status = 'active'
    join discovery_settings d on d.account_id = p.account_id
    join lateral (
        -- **Ordered by the numeric suffix, never by the id.** Question ids sort
        -- lexically as q1 < q10 < q11 < q12 < q13 < q2 < q3, so `order by
        -- question_id` would build every answer vector in the wrong order and
        -- score every pair against the wrong grids -- in range, with no error.
        select
            array_agg(qa.option_index order by substring(qa.question_id from 2)::int)
                filter (where substring(qa.question_id from 2)::int <= 13) as ans,
            array_agg(qa.option_index order by substring(qa.question_id from 2)::int)
                filter (where substring(qa.question_id from 2)::int >= 14) as req,
            count(*) as answered
        from questionnaire_answers qa
        where qa.account_id = p.account_id
    ) a on true
    join lateral (
        select
            case when exists (
                select 1 from subscriptions s
                where s.account_id = p.account_id and s.expires_at > now()
            ) then 7 else 5 end as capacity,
            (select count(*) from pairings pr
              where pr.night > _night - 2
                and p.account_id in (pr.lo_account, pr.hi_account)
                and not exists (
                    select 1 from dismissals dm
                    where dm.night = pr.night
                      and dm.account_id = p.account_id
                      and dm.other_account_id =
                          case when pr.lo_account = p.account_id
                               then pr.hi_account else pr.lo_account end
                ))::smallint as retained,
            (select count(*) from conversations c
              where c.state = 'open'
                and p.account_id in (c.lo_account, c.hi_account))
              >= case when exists (
                    select 1 from subscriptions s
                    where s.account_id = p.account_id and s.expires_at > now()
                 ) then 15 else 10 end as is_held
    ) cap on true
    -- A half-answered questionnaire would be scored against defaults it never
    -- gave. Onboarding does not allow it; a question added later would.
    where a.answered = 16;

    get diagnostics n = row_count;
    return n;
end;
$$;


-- --------------------------------------------------------- who could meet whom

create or replace function private.match_build_edges(_night date, _seed bigint)
returns integer language plpgsql security definer
set search_path = public, extensions as $$
declare
    n integer;
begin
    delete from match_edges where night = _night;

    -- `materialized` so the pair join runs once rather than once per branch of
    -- the union. It is the expensive half of the night.
    insert into match_edges (night, account_id, other_id, milli, tie, rank)
    with candidate as materialized (
        select * from private.match_candidates(_night, _seed)
    )
    select night, account_id, other_id, milli, tie,
           row_number() over (partition by account_id
                              order by milli desc, tie asc)
    from (
        -- Both directions from one evaluation of the pair, so the two halves of a
        -- mutual rule cannot disagree with each other. Not aliased `both`, which
        -- is a reserved word -- it appears in `trim(both ...)`.
        select _night as night, c.a_id as account_id, c.b_id as other_id, c.milli, c.tie
          from candidate c
        union all
        select _night, c.b_id, c.a_id, c.milli, c.tie
          from candidate c
    ) directed;

    get diagnostics n = row_count;
    return n;
end;
$$;


-- The pair test itself, once, unordered. Split out so the two directions above are
-- provably the same evaluation rather than two copies of a rule.
create or replace function private.match_candidates(_night date, _seed bigint)
returns table (a_id uuid, b_id uuid, milli integer, tie bytea)
language sql stable security definer
set search_path = public, extensions as $$
    select
        a.account_id, b.account_id,
        (select sum(c.milli)::integer
           from generate_subscripts(a.ans, 1) k
           join compatibility_cells c
             on c.question_id = 'q' || k
            and c.a = a.ans[k] and c.b = b.ans[k]),
        extensions.digest(
            _seed::text || '|' ||
            least(a.account_id, b.account_id)::text || '|' ||
            greatest(a.account_id, b.account_id)::text, 'sha256')
    from match_people a
    join match_people b
      on b.night = a.night
     and b.account_id > a.account_id
    where a.night = _night
      and a.need > 0 and b.need > 0

      -- Orientation, both ways.
      and b.gender = any(a.seeking) and a.gender = any(b.seeking)

      -- Age, both ways.
      and b.age between a.min_age and a.max_age
      and a.age between b.min_age and b.max_age

      -- Distance, both ways. **Not `least(a.radius, b.radius)`** -- a slider at
      -- 100 reads "Anywhere" and means no filter at all on that side. Clamping
      -- such a person to a 100-mile circle puts the upstate towns out of
      -- everybody's reach and manufactures a starvation catastrophe the settings
      -- never caused.
      and (a.radius >= 100 or private.arch_miles(a.lat, a.lon, b.lat, b.lon) <= a.radius)
      and (b.radius >= 100 or private.arch_miles(a.lat, a.lon, b.lat, b.lon) <= b.radius)

      -- The three requirement questions. All three must resolve, or a question
      -- that grew an option would silently stop filtering.
      and (select count(*) = 3 and bool_and(rc.allowed)
             from generate_subscripts(a.req, 1) k
             join requirement_cells rc
               on rc.question_id = 'q' || (13 + k)
              and rc.a = a.req[k] and rc.b = b.req[k])

      -- Blocks, either direction, never saying which.
      and not exists (
          select 1 from blocks bl
          where (bl.blocker_id = a.account_id and bl.blocked_id = b.account_id)
             or (bl.blocker_id = b.account_id and bl.blocked_id = a.account_id))

      -- Already met recently. The cooldown is what stops the same faces
      -- recurring, and also what strands anybody with a short list -- the
      -- simulation measures that trade directly.
      and not exists (
          select 1 from encounters en
          where en.account_id = a.account_id
            and en.other_account_id = b.account_id
            and en.last_night > _night - private.match_cooldown())
$$;


-- ----------------------------------------------------------------- the rounds

create or replace function private.match_rounds(_night date, _seed bigint)
returns integer language plpgsql security definer
set search_path = public, extensions as $$
declare
    rounds integer;
    r integer;
    actor record;
    partner uuid;
    made integer := 0;
begin
    delete from match_state where night = _night;
    insert into match_state (night, account_id, need)
    select night, account_id, need from match_people
     where night = _night and need > 0;

    select coalesce(max(need), 0) into rounds from match_state where night = _night;

    for r in 1 .. rounds loop
        -- The order is snapshotted once per round and then iterated without
        -- re-sorting, exactly as `match.py` does. A stale order is part of the
        -- algorithm rather than a bug: re-sorting after every pairing would be a
        -- different, slower algorithm.
        for actor in
            select s.account_id,
                   (select count(*)
                      from match_edges e
                      join match_state s2
                        on s2.night = e.night and s2.account_id = e.other_id
                     where e.night = _night and e.account_id = s.account_id
                       and s2.filled < s2.need
                       and not (e.other_id = any(s.taken))) as live
              from match_state s
             where s.night = _night and s.filled < s.need
             order by live asc, s.filled asc,
                      extensions.digest(_seed::text || '|' || s.account_id::text
                                        || '|' || s.account_id::text, 'sha256') asc
        loop
            -- State has moved since the snapshot, so re-check before acting.
            continue when (select filled >= need from match_state
                            where night = _night and account_id = actor.account_id);
            continue when actor.live = 0;

            select e.other_id into partner
              from match_edges e
              join match_state s2
                on s2.night = e.night and s2.account_id = e.other_id
              join match_state me
                on me.night = e.night and me.account_id = e.account_id
             where e.night = _night and e.account_id = actor.account_id
               and s2.filled < s2.need
               and not (e.other_id = any(me.taken))
             order by e.rank
             limit 1;

            if partner is null then
                continue;
            end if;

            update match_state
               set filled = filled + 1,
                   taken = taken || partner
             where night = _night and account_id = actor.account_id;
            update match_state
               set filled = filled + 1,
                   taken = taken || actor.account_id
             where night = _night and account_id = partner;

            made := made + 1;
        end loop;
    end loop;

    return made;
end;
$$;


-- ------------------------------------------------------------------- the job

create or replace function private.run_nightly_match(_force boolean default false)
returns match_runs language plpgsql security definer
set search_path = public, extensions as $$
declare
    _night date := private.arch_night();
    _seed bigint;
    run match_runs;
    n_people integer;
    n_edges integer;
    n_pairs integer;
begin
    -- **Scheduled hourly and guarded here, not scheduled once at 13:00 UTC.**
    -- pg_cron runs on UTC and 9am New York is 14:00 UTC in January but 13:00 in
    -- July, so a fixed expression delivers an hour early for seven months. The
    -- guard also means a tick the scheduler misses is picked up by the next one,
    -- and the roster is late rather than absent.
    if not _force
       and extract(hour from now() at time zone 'America/New_York') < 9 then
        return null;
    end if;

    -- One run per night. The insert is the lock: if it inserted nothing, tonight
    -- has already been built.
    _seed := ('x' || substr(md5(_night::text), 1, 8))::bit(32)::bigint;
    insert into match_runs (night, seed) values (_night, _seed)
    on conflict (night) do nothing
    returning * into run;
    if run.night is null then
        return null;
    end if;

    -- A slow run must not overlap the next tick.
    if not pg_try_advisory_lock(hashtext('arch-nightly-match')) then
        delete from match_runs where night = _night and finished_at is null;
        return null;
    end if;

    n_people := private.match_population(_night);
    n_edges := private.match_build_edges(_night, _seed);
    n_pairs := private.match_rounds(_night, _seed);

    -- One row per pair, holding both directions, so a roster that exists in one
    -- direction cannot be written.
    insert into pairings (night, lo_account, hi_account, score)
    select _night,
           least(s.account_id, t.other),
           greatest(s.account_id, t.other),
           e.milli / 1000.0
      from match_state s
      cross join lateral unnest(s.taken) as t(other)
      join match_edges e
        on e.night = _night and e.account_id = s.account_id and e.other_id = t.other
     where s.night = _night
       and s.account_id < t.other
    on conflict (night, lo_account, hi_account) do nothing;

    -- Both directions, so the cooldown is symmetric.
    insert into encounters (account_id, other_account_id, last_night)
    select x.a, x.b, _night from (
        select lo_account as a, hi_account as b from pairings where night = _night
        union all
        select hi_account, lo_account from pairings where night = _night
    ) x
    on conflict (account_id, other_account_id)
      do update set last_night = excluded.last_night;

    update match_runs
       set finished_at = now(),
           people = n_people,
           edges = n_edges,
           pairs = n_pairs,
           held = (select count(*) from match_people where night = _night and held),
           empty = (select count(*) from match_state
                     where night = _night and filled = 0)
     where night = _night
    returning * into run;

    perform pg_advisory_unlock(hashtext('arch-nightly-match'));
    return run;
end;
$$;

-- Never granted to a client. Unlike `start_conversation` and `delete_account`,
-- this one is not the API -- a client that could run it could put itself in
-- anybody's roster, which is the one thing mutual pairing exists to stop.
revoke all on function private.run_nightly_match(boolean) from public, anon, authenticated;
revoke all on function private.match_population(date) from public, anon, authenticated;
revoke all on function private.match_build_edges(date, bigint) from public, anon, authenticated;
revoke all on function private.match_candidates(date, bigint) from public, anon, authenticated;
revoke all on function private.match_rounds(date, bigint) from public, anon, authenticated;
