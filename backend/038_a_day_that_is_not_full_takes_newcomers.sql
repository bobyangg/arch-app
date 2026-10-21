-- Through the day, a newcomer is matched with anybody whose day is not full.
--
-- 037 matched a newcomer on arrival with people who had "a slot open now".
-- Two things change.
--
-- **A day's allowance is counted, not what is left of it.** Five a day, seven
-- with Premium, and a person removed during the day still counts towards it. So
-- somebody the 9am run left at three can be given two newcomers through the
-- day; somebody who had five and dismissed two waits for tomorrow like
-- everybody else. 037 asked how many pairings were still live, which made
-- "removed" and "never had" look the same.
--
--   used today = the pairings still live when this morning's run began
--                (`match_people.retained`, the run's own snapshot)
--              + every pairing made since, by the run or by an arrival,
--                whether or not it has since been dismissed
--
-- A day runs from one 9am to the next (`arch_roster_day`), so a newcomer at 2am
-- counts against the day that began yesterday morning -- the roster on screen at
-- 2am -- and not against the one the 9am run is about to make.
--
-- **A newcomer is anybody no morning run has seen yet.** 037 said "never
-- paired or met", which a newcomer stops being the moment another newcomer's
-- arrival pairs them -- so whoever finished onboarding second took one person
-- from whoever finished first and left them with that one. Now everybody who
-- finished onboarding since this morning's run is a newcomer until tomorrow's,
-- and gets the rest of today's allowance however it was started.
--
-- **The server looks for newcomers too.** 037 relied on the app asking as
-- onboarding finished, so anybody on a build from before it, or whose phone
-- lost the connection at that moment, waited for 9am. Every five minutes
-- `sweep_arrivals` gives every newcomer the same arrival the app would have
-- asked for. The app still asks, because that is the one that lands before the
-- first roster is drawn; whichever comes second finds today's allowance already
-- given and does nothing.
--
-- Everything else is 037's: the same rules as the 9am run from the same
-- functions, one arrival at a time, nothing from 9am until the morning run has
-- finished, and ordinary pairings and encounters.
--
-- In one transaction, with a check at the end, as 037.

begin;

-- "Has a morning run seen them" is asked of every arrival and every sweep.
create index if not exists match_people_account_idx on match_people (account_id);

-- Which day a moment belongs to: the one that began at the most recent 9am in
-- New York, where the run keeps its clock.
create or replace function private.arch_roster_day(_at timestamptz default now())
returns date
language sql
stable
set search_path to 'public'
as $function$
    select ((_at at time zone 'America/New_York') - interval '9 hours')::date
$function$;

-- How much of a day's allowance somebody has had, removals included.
create or replace function private.match_used_today(_account uuid, _day date)
returns integer
language sql
stable
security definer
set search_path to 'public'
as $function$
    select (coalesce((select mp.retained from match_people mp
                       where mp.night = _day and mp.account_id = _account), 0)
          + (select count(*) from pairings p
              where _account in (p.lo_account, p.hi_account)
                and private.arch_roster_day(p.created_at) = _day))::integer
$function$;

-- 037's `match_on_arrival`, for any account, so the sweep can give the same
-- arrival as the app. The changes are marked.
create or replace function private.match_arrival(me uuid)
returns integer
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
    today date := private.arch_night();
    roster_day date := private.arch_roster_day();
    -- The 9am run's seed for today, so ties break the way they would there.
    seed bigint := ('x' || substr(md5(today::text), 1, 8))::bit(32)::bigint;
    arriving match_people;
    room integer;
    made integer := 0;
begin
    -- **Changed.** Only for a newcomer: somebody a morning run has already
    -- seen waits for 9am like everybody else.
    if exists (select 1 from match_people where account_id = me) then
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
    -- place. Held until this transaction ends.
    perform pg_advisory_xact_lock(hashtext('arch-match-on-arrival'));

    select * into arriving
      from private.match_population_rows(today) r
     where r.account_id = me;
    -- Not playing yet (no profile, settings or full questionnaire), or paused.
    if not found or arriving.need = 0 then
        return 0;
    end if;
    -- **Changed.** What is left of their own allowance today. Asked again, an
    -- arrival only tops up to five (or seven); it never replaces somebody they
    -- removed.
    room := least(arriving.need,
                  arriving.capacity - private.match_used_today(me, roster_day));
    if room <= 0 then
        return 0;
    end if;

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
           -- **The change.** Room left in today's allowance, counting anybody
           -- they have already removed today -- not merely a slot that is
           -- empty now.
           and o.capacity > private.match_used_today(o.account_id, roster_day)
           and case when me < o.account_id then private.match_allowed(arriving, o, today)
                    else private.match_allowed(o, arriving, today) end
         order by milli desc nulls last, tie asc
         limit room
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

-- What the app calls as onboarding finishes. Same name and answer as 037.
create or replace function public.match_on_arrival()
returns integer
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
begin
    if auth.uid() is null then
        raise exception 'not signed in' using errcode = '28000';
    end if;
    return private.match_arrival(auth.uid());
end;
$function$;

-- Every newcomer, including the ones the app did not ask for. Oldest first, so
-- the people who have waited longest choose first. The three-day bound only
-- keeps an account that never reaches a morning run from being asked about
-- for ever.
create or replace function private.sweep_arrivals()
returns integer
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
    newcomer uuid;
    made integer := 0;
begin
    for newcomer in
        select p.account_id
          from profiles p
          join accounts a on a.id = p.account_id and a.status = 'active'
          join discovery_settings d on d.account_id = p.account_id and not d.paused
         where p.created_at > now() - interval '3 days'
           and not exists (select 1 from match_people mp where mp.account_id = p.account_id)
         order by p.created_at
    loop
        made := made + private.match_arrival(newcomer);
    end loop;
    return made;
end;
$function$;

revoke all on function public.match_on_arrival() from public, anon;
grant execute on function public.match_on_arrival() to authenticated;
revoke all on function private.match_arrival(uuid) from public, anon, authenticated;
revoke all on function private.sweep_arrivals() from public, anon, authenticated;
revoke all on function private.match_used_today(uuid, date) from public, anon, authenticated;
revoke all on function private.arch_roster_day(timestamptz) from public, anon, authenticated;

-- Every five minutes. Off :07, the morning run's minute, by construction:
-- five-minute marks never land on it.
select cron.schedule('arch-arrival-sweep', '*/5 * * * *', 'select private.sweep_arrivals()');

-- ------------------------------------------------------------ the check
do $check$
begin
    perform private.arch_roster_day();
    perform private.match_used_today(gen_random_uuid(), private.arch_roster_day());
    -- An account with no profile is "not playing yet": 0, and nothing written.
    if private.match_arrival(gen_random_uuid()) <> 0 then
        raise exception 'match_arrival paired an account that does not exist';
    end if;
end
$check$;

commit;
