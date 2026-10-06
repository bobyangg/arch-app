-- Deleting an account deletes the person; what the matcher learned from them stays.
--
-- Two halves, asked for together.
--
-- **The person goes.** `delete_account` already removed the profile, photos,
-- prompts, interests, answers, preferences, push tokens, pairings and encounters.
-- It left a handful of the account's own records behind: its dismissals (and
-- other people's dismissals of it), its location changes, its devices' App
-- Attest keys, notifications still queued for it, and its data-export requests.
-- None of those is a safety, legal or purchase record, so they go too. What stays
-- is what the privacy policy says stays: the account row with the Sign in with
-- Apple identifier and no name or email, blocks and reports about the account,
-- removals, purchase records, which terms it accepted, and messages already sent
-- to other people.
--
-- **The introductions stay, with what the matcher saw.** `analytics.introductions`
-- (021) records each introduction under random codes -- score, ranks, and what
-- followed -- and deleting the account destroys the link from the code to the
-- person. What it did not keep was the matcher's inputs, which lived only in the
-- nightly snapshots that 022 deletes with the account and after 90 days. For
-- learning a better matcher those inputs are the point, so each introduction now
-- keeps a copy of what the matcher knew about each side that night:
--
--   age, gender, the thirteen scored answers and the three requirement answers,
--   and how far apart the two were, in whole kilometres.
--
-- Not kept: names, photographs, anything written, who either person was looking
-- for, their age or distance preferences, or a position. Distance is the only
-- trace of where anybody was, and it is the distance between two coarse points.
--
-- The copy is taken by `analytics.record()`, hourly, from `match_people` for the
-- night of the introduction. `delete_account` now runs it first, so an
-- introduction made in the hour before somebody deletes their account is not
-- lost with them.

alter table analytics.introductions
    add column if not exists age_a          smallint,
    add column if not exists age_b          smallint,
    add column if not exists gender_a       text,
    add column if not exists gender_b       text,
    add column if not exists answers_a      smallint[],
    add column if not exists answers_b      smallint[],
    add column if not exists requirements_a smallint[],
    add column if not exists requirements_b smallint[],
    add column if not exists distance_km    smallint;

comment on column analytics.introductions.answers_a is
    'q1..q13 option indices for subject_a, as the matcher scored them that night';
comment on column analytics.introductions.requirements_a is
    'q14..q16 option indices for subject_a, the requirement questions';
comment on column analytics.introductions.distance_km is
    'Great-circle distance between the two coarse positions the matcher used, rounded';

-- Great-circle kilometres between two coarse points, for the line above.
--
-- **Strict, and that is not a nicety.** `least()` skips nulls, so without it a
-- missing position made `least(1, null)` = 1, and the distance came out as half
-- the planet -- 20,015 km -- rather than unknown.
create or replace function analytics.km(lat1 numeric, lon1 numeric, lat2 numeric, lon2 numeric)
returns double precision
language sql
immutable
strict
set search_path to 'pg_catalog'
as $function$
    select 2 * 6371 * asin(least(1, sqrt(
        power(sin(radians((lat2 - lat1)::float8) / 2), 2)
      + cos(radians(lat1::float8)) * cos(radians(lat2::float8))
      * power(sin(radians((lon2 - lon1)::float8) / 2), 2)
    )))
$function$;

revoke all on function analytics.km(numeric, numeric, numeric, numeric) from public, anon, authenticated;

create or replace function analytics.record()
returns void
language plpgsql
security definer
set search_path to 'public', 'analytics'
as $function$
declare
    today date := private.arch_night();
begin
    insert into analytics.subjects (account_id)
    select distinct side.id
      from pairings p
     cross join lateral (values (p.lo_account), (p.hi_account)) as side(id)
     where p.night >= today - 14
    on conflict (account_id) do nothing;

    -- Each introduction, and what the matcher knew about each side that night.
    -- A row recorded before this column set existed is filled in on the next
    -- pass, while the night's snapshot is still there to fill it from.
    insert into analytics.introductions as i (
        night, subject_a, subject_b, score, rank_a, rank_b,
        age_a, age_b, gender_a, gender_b,
        answers_a, answers_b, requirements_a, requirements_b, distance_km)
    select p.night, sa.subject, sb.subject, p.score,
           (select e.rank from match_edges e
             where e.night = p.night and e.account_id = p.lo_account and e.other_id = p.hi_account),
           (select e.rank from match_edges e
             where e.night = p.night and e.account_id = p.hi_account and e.other_id = p.lo_account),
           ma.age, mb.age, ma.gender::text, mb.gender::text,
           ma.ans, mb.ans, ma.req, mb.req,
           round(analytics.km(ma.lat, ma.lon, mb.lat, mb.lon))::smallint
      from pairings p
      join analytics.subjects sa on sa.account_id = p.lo_account
      join analytics.subjects sb on sb.account_id = p.hi_account
      left join match_people ma on ma.night = p.night and ma.account_id = p.lo_account
      left join match_people mb on mb.night = p.night and mb.account_id = p.hi_account
     where p.night >= today - 14
    on conflict (night, subject_a, subject_b) do update
       set age_a          = coalesce(i.age_a,          excluded.age_a),
           age_b          = coalesce(i.age_b,          excluded.age_b),
           gender_a       = coalesce(i.gender_a,       excluded.gender_a),
           gender_b       = coalesce(i.gender_b,       excluded.gender_b),
           answers_a      = coalesce(i.answers_a,      excluded.answers_a),
           answers_b      = coalesce(i.answers_b,      excluded.answers_b),
           requirements_a = coalesce(i.requirements_a, excluded.requirements_a),
           requirements_b = coalesce(i.requirements_b, excluded.requirements_b),
           distance_km    = coalesce(i.distance_km,    excluded.distance_km);

    with live as (
        select p.night, p.lo_account as a, p.hi_account as b, p.created_at as introduced,
               sa.subject as subject_a, sb.subject as subject_b
          from pairings p
          join analytics.subjects sa on sa.account_id = p.lo_account
          join analytics.subjects sb on sb.account_id = p.hi_account
         where p.night >= today - 14
    ),
    outcome as (
        select l.night, l.subject_a, l.subject_b,
               c.id as conversation_id, c.created_at as started, c.opened_by,
               case when c.opened_by = l.a then l.subject_a
                    when c.opened_by = l.b then l.subject_b end as opener,
               exists (
                   select 1 from dismissals d
                    where d.night = l.night
                      and d.account_id in (l.a, l.b)
                      and d.other_account_id in (l.a, l.b)
               ) as any_dismissal
          from live l
          left join conversations c
            on c.lo_account = l.a and c.hi_account = l.b
           and c.created_at >= l.introduced
           and c.created_at <  l.introduced + interval '3 days'
    )
    update analytics.introductions i
       set conversation_at     = o.started,
           opener              = o.opener,
           replied             = coalesce((select bool_or(m.sender_id <> o.opened_by)
                                             from messages m where m.conversation_id = o.conversation_id), false),
           messages_first_week = coalesce((select count(*)
                                             from messages m where m.conversation_id = o.conversation_id
                                              and m.created_at < o.started + interval '7 days'), 0),
           dismissed           = o.any_dismissal and o.conversation_id is null,
           updated_at          = now()
      from outcome o
     where i.night = o.night and i.subject_a = o.subject_a and i.subject_b = o.subject_b;

    -- Ninety days, as the privacy policy says. The introductions above have
    -- already taken what they keep from these.
    delete from match_edges  where night < today - 90;
    delete from match_state  where night < today - 90;
    delete from match_people where night < today - 90;
end;
$function$;

create or replace function public.delete_account()
returns table(ok boolean)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
    me uuid := auth.uid();
begin
    if me is null then
        raise exception 'not signed in' using errcode = '28000';
    end if;

    -- First, while everything is still here: copy this person's introductions,
    -- with what the matcher saw and how each one went, into the analytics
    -- record. Deleting must not wait on analytics, so a failure here is logged
    -- and the deletion goes on.
    begin
        perform analytics.record();
    exception when others then
        raise warning 'analytics.record() failed during delete_account: %', sqlerrm;
    end;

    update conversations
       set state = 'ended'
     where me in (lo_account, hi_account)
       and state <> 'ended';

    delete from pairings where me in (lo_account, hi_account);
    delete from encounters where me in (account_id, other_account_id);
    delete from dismissals where me in (account_id, other_account_id);

    delete from questionnaire_answers where account_id = me;
    delete from profile_prompts where account_id = me;
    delete from profile_interests where account_id = me;
    delete from photos where account_id = me;
    delete from discovery_settings where account_id = me;
    delete from place_changes where account_id = me;
    delete from push_tokens where account_id = me;
    delete from push_outbox where recipient_id = me;
    delete from account_devices where account_id = me;
    delete from export_requests where account_id = me;
    delete from profiles where account_id = me;

    delete from blocks where blocker_id = me;

    -- `status` is untouched. A moderator's decision outlives this function, and
    -- nothing this function does is a moderator's decision.
    update accounts
       set deleted_at = now(),
           apple_email = null,
           apple_name = null
     where id = me;

    return query select true;
end;
$function$;

-- Fill the introductions recorded before this, where the snapshot still exists.
-- Older than 14 nights, so `analytics.record()` does not reach them; the person
-- must still have a code, so a deleted account's are beyond reach -- their
-- snapshots were deleted with them anyway.
update analytics.introductions i
   set age_a = ma.age, age_b = mb.age,
       gender_a = ma.gender::text, gender_b = mb.gender::text,
       answers_a = ma.ans, answers_b = mb.ans,
       requirements_a = ma.req, requirements_b = mb.req,
       distance_km = round(analytics.km(ma.lat, ma.lon, mb.lat, mb.lon))::smallint
  from analytics.subjects sa, analytics.subjects sb, match_people ma, match_people mb
 where i.age_a is null
   and sa.subject = i.subject_a and sb.subject = i.subject_b
   and ma.night = i.night and ma.account_id = sa.account_id
   and mb.night = i.night and mb.account_id = sb.account_id;

select analytics.record();
