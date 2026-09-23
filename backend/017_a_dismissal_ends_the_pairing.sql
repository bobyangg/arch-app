-- A dismissal ends the pairing. It ended it on one side only.
--
-- The app says this in three places and the schema was built for it:
--
--   HelpPages.swift:50  "When somebody goes, Arch tells you a slot opened --
--                        never who left, and never why. Dismissing you and
--                        writing to you look identical from your side."
--   MockData.swift:543  `SlotOpening.theirs` -- "They went. You are not told
--                        which of the two things they did."
--   MockData.swift:550  "You dismissing someone and someone dismissing you
--                        produce the identical state."
--
-- None of it was true. A dismissal was read only against the person who wrote it,
-- so somebody who dismissed you stayed in your roster for the full two nights,
-- holding one of your five slots, and could still be written to. The privacy rule
-- was kept -- you were never told -- by not implementing the behaviour it
-- describes.
--
-- Writing to somebody already worked this way: `start_conversation` inserts a
-- dismissal for *both* sides, because the pair has stopped being somebody to
-- consider at both ends. That is the precedent this follows. A dismissal row for
-- a pair, written by either of them, ends that pairing for both.
--
-- **What is deliberately not changed:** nothing tells the reader why a slot
-- opened. Every empty slot is built as `.yours`, the matcher sends no reason, and
-- `start_conversation` refuses with the same 'not in your roster' it already
-- used -- so dismissing somebody and being dismissed by them stay
-- indistinguishable. The behaviour changes; the disclosure does not.

-- The predicate, in one place. `security definer` because `dismissals` is
-- readable only by its own author under `dismissals_own`, so a policy asking this
-- question inline would see only the asker's half and answer no every time it
-- mattered.
create or replace function private.arch_pairing_ended(_night date, _lo uuid, _hi uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
    select exists (
        select 1 from dismissals dm
         where dm.night = _night
           and dm.account_id in (_lo, _hi)
           and dm.other_account_id in (_lo, _hi)
           and dm.account_id <> dm.other_account_id
    )
$$;

revoke all on function private.arch_pairing_ended(date, uuid, uuid) from public;
grant execute on function private.arch_pairing_ended(date, uuid, uuid) to authenticated;

-- 1. The pairing stops being visible to the side that did not dismiss.
--
-- In the policy rather than in the client, because the client cannot do it: it is
-- allowed to read its own dismissals and nobody else's, which is the rule that
-- keeps a reader from ever learning who dismissed whom. Hiding the row is how the
-- server answers the question without disclosing the answer.
drop policy if exists pairings_mine on pairings;
create policy pairings_mine on pairings for select using (
    ((select auth.uid()) = lo_account or (select auth.uid()) = hi_account)
    and not private.arch_pairing_ended(night, lo_account, hi_account)
);

-- 2. The slot frees on both sides, so tomorrow refills it.
--
-- Without this the slot would be invisible and still held: `need = capacity -
-- retained` would go on reserving it for a pairing the reader can no longer see,
-- and they would lose a person and gain nobody -- exactly the fault the client's
-- one-night roster window had, one layer down.
create or replace function private.match_population(_night date)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare n integer;
begin
    delete from match_people where night = _night;
    insert into match_people (
        night, account_id, gender, seeking, age, min_age, max_age,
        lat, lon, radius, capacity, retained, need, held, ans, req)
    select _night, p.account_id, p.gender, d.seeking,
        extract(year from age(p.birthdate))::smallint, d.min_age, d.max_age,
        p.coarse_lat, p.coarse_lon, d.distance_miles,
        cap.capacity, cap.retained,
        case when d.paused or cap.is_held then 0::smallint
             else greatest(0, cap.capacity - cap.retained)::smallint end,
        cap.is_held, a.ans, a.req
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
            -- Either side. This was `dm.account_id = p.account_id`, which held the
            -- slot open for somebody who had already gone.
            (select count(*) from pairings pr
              where pr.night > _night - 2
                and p.account_id in (pr.lo_account, pr.hi_account)
                and not private.arch_pairing_ended(pr.night, pr.lo_account, pr.hi_account)
            )::smallint as retained,
            (select count(*) from conversations c
              where c.state = 'open' and p.account_id in (c.lo_account, c.hi_account))
              >= case when exists (select 1 from subscriptions s
                    where s.account_id = p.account_id and s.expires_at > now())
                 then 15 else 10 end as is_held
    ) cap on true
    -- A half-answered questionnaire would be scored against defaults it never
    -- gave. Onboarding does not allow it; a question added later would.
    where a.answered = 16;
    get diagnostics n = row_count;
    return n;
end;
$function$;

-- 3. You cannot write to somebody who has gone.
--
-- `start_conversation` is `security definer` and so does not see the policy in
-- (1) -- without this the rule would hold in the app and not in the API, and the
-- reader's own client would be the only thing enforcing it.
--
-- Folded into the existing roster check so it raises the *same* error. A separate
-- message for this case would be the disclosure the rest of this migration goes
-- to trouble to avoid.
create or replace function public.start_conversation(other_account uuid, body text)
returns table(id uuid)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
    me uuid := auth.uid();
    lo uuid;
    hi uuid;
    conversation_id uuid;
    today date := private.arch_night();
begin
    if me is null then
        raise exception 'not signed in' using errcode = '28000';
    end if;
    if me = other_account then
        raise exception 'cannot write to yourself' using errcode = '22023';
    end if;
    if length(trim(body)) = 0 then
        raise exception 'empty message' using errcode = '22023';
    end if;

    -- Blocks stop this in either direction, and the error says nothing about which
    -- way round it went.
    if exists (
        select 1 from blocks
        where (blocker_id = me and blocked_id = other_account)
           or (blocker_id = other_account and blocked_id = me)
    ) then
        raise exception 'not available' using errcode = '42501';
    end if;

    -- You can only write to somebody you were actually given, and only while they
    -- are still there. Without the first half, the account id of anybody on the
    -- service would be enough to message them; without the second, a dismissal
    -- would take somebody out of your roster and leave them reachable anyway.
    if not exists (
        select 1 from pairings p
        where p.night > today - 2
          and ((p.lo_account = me and p.hi_account = other_account)
            or (p.lo_account = other_account and p.hi_account = me))
          and not private.arch_pairing_ended(p.night, p.lo_account, p.hi_account)
    ) then
        raise exception 'not in your roster' using errcode = '42501';
    end if;

    lo := least(me, other_account);
    hi := greatest(me, other_account);

    insert into conversations (lo_account, hi_account, state, opened_by, last_message_at)
    values (lo, hi, 'request', me, now())
    on conflict (lo_account, hi_account) do update
        set last_message_at = now()
    returning conversations.id into conversation_id;

    insert into messages (conversation_id, sender_id, body)
    values (conversation_id, me, body);

    -- The pair has stopped being somebody to consider and started being somebody
    -- to answer, so the slot opens at both ends. Recorded as a dismissal on both
    -- sides because that is what the roster query reads; nobody is told, and it is
    -- indistinguishable from either of them having simply moved on.
    insert into dismissals (account_id, other_account_id, night)
    select x.a, x.b, p.night from pairings p
    cross join lateral (values (me, other_account), (other_account, me)) as x(a, b)
    where p.night > today - 2
      and p.lo_account = lo and p.hi_account = hi
    on conflict do nothing;

    return query select conversation_id;
end;
$function$;
