-- Two people introduced again can talk again.
--
-- A conversation is one row per pair (`unique (lo_account, hi_account)`), and it
-- outlives the pairing that started it: leaving, or the night's dismissal, ends
-- it. The matcher can introduce the same two people again once the cooldown has
-- passed -- it did, on 30 September, for two people whose conversation had ended
-- on the 23rd -- and when one of them wrote, `start_conversation` landed on the
-- old row with `on conflict ... do update set last_message_at = now()`. The state
-- stayed `ended`. The first message went in, because this function is security
-- definer; every reply after it was refused, because `messages_send` only allows
-- a conversation that is a request or open. A new introduction led straight to a
-- conversation nobody could answer.
--
-- Now an ended conversation that a new introduction writes into starts again as
-- a request from whoever wrote. Its earlier messages stay in it: the two of you
-- did talk before, and pretending otherwise would be stranger than showing it.
-- `created_at` is left alone, so the matcher analytics keeps the first
-- conversation tied to the first introduction.
--
-- Everything that decides whether you may write is unchanged: a block still
-- refuses, and the pair must still be in each other's roster tonight.

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

    -- Every `case` reads the row as it was before this update, so an ended
    -- conversation becomes a request opened by `me`, and a live one is only
    -- touched.
    insert into conversations as c (lo_account, hi_account, state, opened_by, last_message_at)
    values (lo, hi, 'request', me, now())
    on conflict (lo_account, hi_account) do update
        set last_message_at = now(),
            state     = case when c.state = 'ended' then 'request'::conversation_state else c.state end,
            opened_by = case when c.state = 'ended' then me else c.opened_by end
    returning c.id into conversation_id;

    insert into messages (conversation_id, sender_id, body)
    values (conversation_id, me, body);

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
