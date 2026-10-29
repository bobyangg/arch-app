-- Premium is eight people a day, not seven.
--
-- The whole of the number lives here: `match_population_rows` gives each person
-- their capacity, and everything else reads it from there -- the 9am run's
-- need, an arrival's room (`match_used_today` against `capacity`, 038), and the
-- `match_people` snapshot. So this is 037's function with one figure changed,
-- 7 to 8. Free stays at five; the conversation limits (ten, fifteen) do not
-- change.
--
-- A subscriber's next morning fills to eight; somebody mid-day with seven
-- already given can be given one more newcomer the same day, because 038
-- counts today's allowance against capacity.

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
            -- **Eight with Premium** (was seven), five without.
            case when exists (select 1 from subscriptions s
                where s.account_id = p.account_id and s.expires_at > now())
                then 8 else 5 end as capacity,
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

revoke all on function private.match_population_rows(date) from public, anon, authenticated;
