-- A newcomer is matched on arrival.
--
-- Somebody who finishes onboarding at 2pm used to wait until 9 the next
-- morning for anybody at all: the roster is built once a day, and they were not
-- in it. Their first look at Arch was an empty page.
--
-- Meanwhile, every morning some people end up with fewer than five -- the run
-- records how many in `match_runs.empty` -- and through the day more slots open
-- as people dismiss somebody or write to them. So when somebody finishes
-- onboarding, `match_on_arrival()` pairs them with people who have a slot open
-- right now, and nobody else.
--
-- **The same rules as the 9am run, from the same functions.** Who is playing,
-- and with how many open slots, is `private.match_population_rows`; whether two
-- people may meet is `private.match_allowed`; how well they fit is
-- `private.match_milli`. The 9am run now uses exactly these -- this migration
-- moves its rules into them without changing a single one -- so the two cannot
-- drift apart: gender and age both ways, distance both ways, the three
-- requirement questions, blocks, the seven-night cooldown, paused profiles,
-- and the hold on anybody with too many open conversations.
--
-- **Nobody loses anybody.** The people paired with the newcomer only have an
-- empty slot filled, and they are usually the ones who were short. The
-- newcomer's pairings are ordinary `pairings` rows for today: they read,
-- expire and count against tomorrow's run like any other, and the cooldown is
-- recorded in `encounters` the same way.
--
-- **The catch.** In a small or remote area there may be nobody with a free
-- slot, so a newcomer can get fewer than five, or none, until the morning.
--
-- **Only on arrival.** An account that has ever been paired, or met anybody,
-- gets nothing from this: everybody else waits for 9am, so it is not a way to
-- top up a roster during the day. Arrivals are taken one at a time, so two
-- people finishing onboarding together cannot both take somebody's last slot;
-- and nothing is done from 9am until that morning's run has finished, so an
-- arrival never lands in the middle of the batch.
--
-- In one transaction, with a check at the end that the functions run: if
-- anything here fails, nothing here is applied, and the 9am run keeps working
-- as it did.

begin;

-- ------------------------------------------------------------ who is playing
--
-- The population, as rows, for any night. `match_population` writes them for
-- the 9am run; `match_on_arrival` reads them for the people with a slot open
-- now. The body is 017's, unchanged except that each column is cast to the
-- type `match_people` holds, which a function returning those rows requires.
create or replace function private.match_population_rows(_night date)
returns setof match_people
language sql
stable
security definer
set search_path to 'public'
as $function$
    select _night::date,
        p.account_id::uuid,
        p.gender::gender,
        d.seeking::gender[],
        extract(year from age(p.birthdate))::smallint,
        d.min_age::smallint,
        d.max_age::smallint,
        p.coarse_lat::numeric,
        p.coarse_lon::numeric,
        d.distance_miles::smallint,
        cap.capacity::smallint,
        cap.retained::smallint,
        (case when d.paused or cap.is_held then 0
              else greatest(0, cap.capacity - cap.retained) end)::smallint,
        cap.is_held::boolean,
        a.ans::smallint[],
        a.req::smallint[]
    from profiles p
    join accounts acc on acc.id = p.account_id and acc.status = 'active'
    join discovery_settings d on d.account_id = p.account_id
    join lateral (
        -- Ordered by the numeric suffix, never by the id. Question ids sort
        -- lexically as q1 < q10 < q11 < q12 < q13 < q2 < q3, so `order by
        -- question_id` would build every answer vector in the wrong order and
        -- score every pair against the wrong grids, in range, with no error.
        select
            array_agg(qa.option_index order by substring(qa.question_id from 2)::int)
                filter (where substring(qa.question_id from 2)::int <= 13) as ans,
            array_agg(qa.option_index order by substring(qa.question_id from 2)::int)
                filter (where substring(qa.question_id from 2)::int >= 14) as req,
            count(*) as answered
        from questionnaire_answers qa where qa.account_id = p.account_id
    ) a on true
    join lateral (
        select
            case when exists (select 1 from subscriptions s
                where s.account_id = p.account_id and s.expires_at > now())
                then 7 else 5 end as capacity,
            -- Either side: a dismissal by either of them ends the pairing.
            (select count(*) from pairings pr
              where pr.night > _night - 2
                and p.account_id in (pr.lo_account, pr.hi_account)
                and not private.arch_pairing_ended(pr.night, pr.lo_account, pr.hi_account)
            ) as retained,
            (select count(*) from conversations c
              where c.state = 'open' and p.account_id in (c.lo_account, c.hi_account))
              >= case when exists (select 1 from subscriptions s
                    where s.account_id = p.account_id and s.expires_at > now())
                 then 15 else 10 end as is_held
    ) cap on true
    -- A half-answered questionnaire would be scored against defaults it never
    -- gave. Onboarding does not allow it; a question added later would.
    where a.answered = 16
$function$;

create or replace function private.match_population(_night date)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare n integer;
begin
    delete from match_people where night = _night;
    insert into match_people
    select * from private.match_population_rows(_night);
    get diagnostics n = row_count;
    return n;
end;
$function$;


-- ------------------------------------------------------- who could meet whom
--
-- The pair test, once, for two people in `match_people` form. `pa` is always
-- the one with the lower account id, as in the 9am run, because the
-- requirement grids are read in that order. Not `security definer` and not
-- given a search path, so that Postgres can fold it into the 9am run's query
-- rather than call it once per pair -- which is also why every table in it is
-- named with its schema.
create or replace function private.match_allowed(pa match_people, pb match_people, _night date)
returns boolean
language sql
stable
as $function$
    select
        -- Orientation, both ways.
        pb.gender = any(pa.seeking) and pa.gender = any(pb.seeking)

        -- Age, both ways.
        and pb.age between pa.min_age and pa.max_age
        and pa.age between pb.min_age and pb.max_age

        -- Distance, both ways. **Not `least(radius)`** -- a slider at 100 reads
        -- "Anywhere" and means no filter at all on that side.
        and (pa.radius >= 100 or private.arch_miles(pa.lat, pa.lon, pb.lat, pb.lon) <= pa.radius)
        and (pb.radius >= 100 or private.arch_miles(pa.lat, pa.lon, pb.lat, pb.lon) <= pb.radius)

        -- The three requirement questions. All three must resolve, or a question
        -- that grew an option would silently stop filtering.
        and (select count(*) = 3 and bool_and(rc.allowed)
               from generate_subscripts(pa.req, 1) k
               join public.requirement_cells rc
                 on rc.question_id = 'q' || (13 + k)
                and rc.a = pa.req[k] and rc.b = pb.req[k])

        -- Blocks, either direction, never saying which.
        and not exists (
            select 1 from public.blocks bl
            where (bl.blocker_id = pa.account_id and bl.blocked_id = pb.account_id)
               or (bl.blocker_id = pb.account_id and bl.blocked_id = pa.account_id))

        -- Already met recently.
        and not exists (
            select 1 from public.encounters en
            where en.account_id = pa.account_id
              and en.other_account_id = pb.account_id
              and en.last_night > _night - private.match_cooldown())
$function$;

-- How well two people fit, in integer thousandths. `pa` the lower id, as above.
create or replace function private.match_milli(pa match_people, pb match_people)
returns integer
language sql
stable
as $function$
    select sum(c.milli)::integer
      from generate_subscripts(pa.ans, 1) k
      join public.compatibility_cells c
        on c.question_id = 'q' || k
       and c.a = pa.ans[k] and c.b = pb.ans[k]
$function$;

-- The 9am run's candidate pairs, from the two functions above. Same pairs, same
-- scores, same tie-breaks as before.
create or replace function private.match_candidates(_night date, _seed bigint)
returns table (a_id uuid, b_id uuid, milli integer, tie bytea)
language sql
stable
security definer
set search_path = public, extensions
as $function$
    select
        a.account_id, b.account_id,
        private.match_milli(a, b),
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
      and private.match_allowed(a, b, _night)
$function$;


-- ------------------------------------------------------------- on arrival

-- Pairs the caller with people who have a slot open now, best fit first, up to
-- the caller's own capacity. Returns how many pairings it made: often five,
-- sometimes fewer, and none for anybody who has been matched before.
create or replace function public.match_on_arrival()
returns integer
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
    me uuid := auth.uid();
    today date := private.arch_night();
    -- The 9am run's seed for today, so ties break the way they would there.
    seed bigint := ('x' || substr(md5(today::text), 1, 8))::bit(32)::bigint;
    arriving match_people;
    made integer := 0;
begin
    if me is null then
        raise exception 'not signed in' using errcode = '28000';
    end if;

    -- Only on arrival. Anybody who has been paired, or has met anybody, waits
    -- for 9am like everybody else.
    if exists (select 1 from pairings where me in (lo_account, hi_account))
       or exists (select 1 from encounters where account_id = me) then
        return 0;
    end if;

    -- Never in the middle of the batch: from 9am until this morning's run has
    -- finished, the run will take them itself.
    if extract(hour from now() at time zone 'America/New_York') >= 9
       and not exists (select 1 from match_runs
                        where night = today and finished_at is not null) then
        return 0;
    end if;

    -- One arrival at a time, so two newcomers cannot both take somebody's last
    -- open slot. Held until this transaction ends.
    perform pg_advisory_xact_lock(hashtext('arch-match-on-arrival'));

    select * into arriving
      from private.match_population_rows(today) r
     where r.account_id = me;
    -- Not playing yet (no profile, settings or full questionnaire), or paused.
    if not found or arriving.need = 0 then
        return 0;
    end if;

    -- Everybody with a slot open now who passes the same test as at 9am, best
    -- fit first, ties broken by the same hash.
    insert into pairings (night, lo_account, hi_account, score)
    select today, least(me, c.other_id), greatest(me, c.other_id), c.milli / 1000.0
      from (
        select o.account_id as other_id,
               case when me < o.account_id then private.match_milli(arriving, o)
                    else private.match_milli(o, arriving) end as milli,
               extensions.digest(
                   seed::text || '|' ||
                   least(me, o.account_id)::text || '|' ||
                   greatest(me, o.account_id)::text, 'sha256') as tie
          from private.match_population_rows(today) o
         where o.account_id <> me
           and o.need > 0
           and case when me < o.account_id then private.match_allowed(arriving, o, today)
                    else private.match_allowed(o, arriving, today) end
         order by milli desc nulls last, tie asc
         limit arriving.need
      ) c
    on conflict (night, lo_account, hi_account) do nothing;
    get diagnostics made = row_count;

    -- Both directions, so the cooldown is symmetric, as at 9am.
    insert into encounters (account_id, other_account_id, last_night)
    select x.a, x.b, today
      from pairings p
     cross join lateral (values (p.lo_account, p.hi_account),
                                (p.hi_account, p.lo_account)) as x(a, b)
     where p.night = today and me in (p.lo_account, p.hi_account)
    on conflict (account_id, other_account_id)
      do update set last_night = excluded.last_night;

    return made;
end;
$function$;

-- The API, for signed-in callers only; the rest stays out of reach.
revoke all on function public.match_on_arrival() from public, anon;
grant execute on function public.match_on_arrival() to authenticated;
revoke all on function private.match_population_rows(date) from public, anon, authenticated;
revoke all on function private.match_allowed(match_people, match_people, date) from public, anon, authenticated;
revoke all on function private.match_milli(match_people, match_people) from public, anon, authenticated;


-- ------------------------------------------------------------ the check
--
-- Runs each function once, so a mistake fails here -- and takes the whole
-- migration with it -- rather than at nine tomorrow morning.
do $check$
declare
    last date;
begin
    perform count(*) from private.match_population_rows(private.arch_night());
    select max(night) into last from match_people;
    if last is not null then
        perform count(*) from private.match_candidates(last, 0);
    end if;
end
$check$;

commit;
