-- A dismissal takes effect at the next refill, not the moment you tap it.
--
-- 017 made a dismissal end the pairing for both people immediately, which is
-- right about *whether* it is mutual and wrong about *when*. Dismissing somebody
-- is a decision made in a second, and it took the other person's chance to write
-- to you away before they had opened the app that morning. It also gave the
-- person who tapped it nothing: the roster is built once a day, so the slot could
-- not refill any sooner, and all the speed bought was irreversibility.
--
-- Now a dismissal is scheduled rather than applied. It lands at the next nine in
-- the morning, New York -- the same instant the new roster is built, so the
-- person leaves and their replacement arrives in one move rather than two.
-- Until then:
--
--   * the other person sees no change at all, and can still write to you
--   * you can still write to them
--   * you can take it back
--
-- and none of that is visible to them, because a dismissal you cancelled has to
-- be indistinguishable from one you never made.
--
-- **Writing to somebody is still immediate.** That is a different act with a
-- different meaning -- they have stopped being someone to consider and started
-- being someone to answer -- and the roster says so the moment you send. So the
-- row carries *when* it applies rather than the two being told apart by which
-- function wrote them.
--
-- The client no longer writes these rows at all. It used to insert them directly,
-- which meant the schedule would have been the client's to choose: an app that
-- could set `effective_at` could dismiss you immediately and take away exactly the
-- chance this migration exists to give. Two functions own it instead, and
-- `dismissals` loses every policy except the one that lets you read your own.

-- When the next roster is built: the next nine in the morning, New York. A
-- dismissal at 11pm lands ten hours later; one at 3am lands at nine the same
-- morning rather than waiting a day and a half for the date to roll twice.
create or replace function private.arch_next_refill(at timestamptz default now())
returns timestamptz
language sql
stable
as $$
    select case
        when (at at time zone 'America/New_York')::time < time '09:00'
        then (((at at time zone 'America/New_York')::date + time '09:00')
              at time zone 'America/New_York')
        else (((at at time zone 'America/New_York')::date + 1 + time '09:00')
              at time zone 'America/New_York')
    end
$$;

alter table dismissals
    add column if not exists effective_at timestamptz;

-- Everything already written was written under the old rule and has already been
-- acted on, so it is in effect now rather than at some future nine.
update dismissals set effective_at = created_at where effective_at is null;

alter table dismissals
    alter column effective_at set not null,
    alter column effective_at set default now();

create index if not exists dismissals_effective
    on dismissals (other_account_id, effective_at);

-- The predicate 017 introduced, with the clock added. A pairing is over when a
-- dismissal for it has *landed*, not when one has been written.
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
           and dm.effective_at <= now()
    )
$$;

-- Reading your own is all the client may do. It needs that much: a dismissal of
-- yours that has not landed yet is what puts somebody in the section at the
-- bottom of your five rather than in it, and only you can see that.
drop policy if exists dismissals_own on dismissals;
create policy dismissals_read on dismissals for select
    using (account_id = (select auth.uid()));

revoke insert, update, delete on dismissals from authenticated;
grant select on dismissals to authenticated;

-- Dismissing: scheduled for the next refill, on every night you hold them.
--
-- One row, not two. `arch_pairing_ended` reads a dismissal from either side, so
-- the pair ends for both when this lands -- which is what 017 established and
-- what makes a roster you were removed from stop holding your slot.
create or replace function public.dismiss_person(other_account uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
    me uuid := auth.uid();
    today date := private.arch_night();
begin
    if me is null then
        raise exception 'not signed in' using errcode = '28000';
    end if;
    if me = other_account then
        raise exception 'cannot dismiss yourself' using errcode = '22023';
    end if;

    -- Stamped with the night of the pairing it cancels. `match_population` frees
    -- a slot only where the dismissal and the pairing agree on the night, so one
    -- written against the wrong night frees nothing and the person is back in the
    -- morning.
    insert into dismissals (account_id, other_account_id, night, effective_at)
    select me, other_account, p.night, private.arch_next_refill()
      from pairings p
     where p.night > today - 2
       and ((p.lo_account = me and p.hi_account = other_account)
         or (p.lo_account = other_account and p.hi_account = me))
    on conflict (account_id, other_account_id, night) do nothing;
end;
$function$;

-- Taking it back, while it is still yours to take back.
--
-- Only rows that have not landed. The one `start_conversation` writes is in
-- effect the moment it is written, so writing to somebody cannot be undone by
-- this -- a message that has been delivered is not a decision you still hold.
create or replace function public.restore_person(other_account uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare me uuid := auth.uid();
begin
    if me is null then
        raise exception 'not signed in' using errcode = '28000';
    end if;
    delete from dismissals
     where account_id = me
       and other_account_id = other_account
       and effective_at > now();
end;
$function$;

revoke all on function public.dismiss_person(uuid) from public;
revoke all on function public.restore_person(uuid) from public;
grant execute on function public.dismiss_person(uuid) to authenticated;
grant execute on function public.restore_person(uuid) to authenticated;

-- `start_conversation` writes its two rows as landing now, because writing to
-- somebody takes effect when you send it. Otherwise unchanged from 017.
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

    if exists (
        select 1 from blocks
        where (blocker_id = me and blocked_id = other_account)
           or (blocker_id = other_account and blocked_id = me)
    ) then
        raise exception 'not available' using errcode = '42501';
    end if;

    -- Still in your roster, or in the section under it: a dismissal that has not
    -- landed does not stop either of you writing, which is the whole point of
    -- letting it wait until nine.
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

    -- Both sides, landing now. A pending dismissal either of them had is
    -- overwritten by this, which is right: the pair has been decided.
    insert into dismissals (account_id, other_account_id, night, effective_at)
    select x.a, x.b, p.night, now() from pairings p
    cross join lateral (values (me, other_account), (other_account, me)) as x(a, b)
    where p.night > today - 2
      and p.lo_account = lo and p.hi_account = hi
    on conflict (account_id, other_account_id, night)
      do update set effective_at = now();

    return query select conversation_id;
end;
$function$;
