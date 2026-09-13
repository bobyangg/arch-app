-- Arch: the operations that have to happen all at once.
--
-- Most of the app is plain table reads and writes through PostgREST, guarded by
-- row-level security. These two are not, because each is several writes that are
-- wrong if only some of them land.
--
-- Both are `security definer`, so they run with the owner's rights rather than the
-- caller's. That makes the checks inside them the only thing standing between a
-- caller and the tables -- every one of them is doing real work, and `search_path`
-- is pinned so a caller cannot shadow a function name with one of their own.

-- ------------------------------------------------------- starting a conversation
--
-- Writing to somebody is the positive action in Arch: there are no likes and no
-- match gate. It creates the conversation and its first message together, because
-- a conversation with no message in it is a request the other person cannot answer
-- and cannot dismiss.
--
-- It also spends the slot at both ends, which is why it is not two inserts from the
-- client: the sender leaves the recipient's roster and the recipient leaves the
-- sender's, and a half-applied version of that leaves somebody holding a slot for a
-- person they are already talking to.
create or replace function start_conversation(other_account uuid, body text)
returns table (id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    lo uuid;
    hi uuid;
    conversation_id uuid;
    today date := (now() at time zone 'America/New_York')::date;
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

    -- You can only write to somebody you were actually given. Without this, the
    -- account id of anybody on the service would be enough to message them, and
    -- the roster would stop meaning anything.
    if not exists (
        select 1 from pairings p
        where p.night > today - 2
          and ((p.lo_account = me and p.hi_account = other_account)
            or (p.lo_account = other_account and p.hi_account = me))
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
$$;

comment on function start_conversation is
    'Creates the conversation and its first message together, and spends the slot at both ends. Refuses anybody not in your current roster.';


-- ------------------------------------------------------------- deleting yourself
--
-- Immediate and permanent, as the screen promises.
--
-- The ordering matters. Conversations are ended *first*, so that the people
-- mid-conversation see exactly what they would see if you had blocked them or
-- simply left -- an ended thread and nothing else. If the profile vanished first,
-- the gap between the profile going and the thread ending would be visible, and
-- the difference would say which had happened.
--
-- The `accounts` row survives, holding the Apple id and a `deleted_at`. That is
-- deliberate: it keeps the id claimed, so somebody removed for abuse cannot delete
-- their account and sign straight back up with the same Apple ID as a stranger.
create or replace function delete_account()
returns table (ok boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
begin
    if me is null then
        raise exception 'not signed in' using errcode = '28000';
    end if;

    update conversations
       set state = 'ended'
     where me in (lo_account, hi_account)
       and state <> 'ended';

    -- Out of every future roster before anything else is touched.
    delete from pairings where me in (lo_account, hi_account);
    delete from encounters where me in (account_id, other_account_id);

    delete from questionnaire_answers where account_id = me;
    delete from profile_prompts where account_id = me;
    delete from profile_interests where account_id = me;
    delete from photos where account_id = me;
    delete from discovery_settings where account_id = me;
    delete from push_tokens where account_id = me;
    delete from profiles where account_id = me;

    -- Blocks they placed go; blocks placed *on* them stay, so that deleting an
    -- account is not a way to clear the record of having been blocked.
    delete from blocks where blocker_id = me;

    update accounts
       set status = 'removed',
           deleted_at = now(),
           apple_email = null,
           apple_name = null
     where id = me;

    return query select true;
end;
$$;

comment on function delete_account is
    'Ends conversations first so that deleting looks identical to blocking or leaving. Keeps the accounts row so the Apple id stays claimed.';


-- ------------------------------------------------------------------ permissions
--
-- `authenticated` is the role a signed-in client has. `anon` is never granted
-- either of these: both begin by refusing a null `auth.uid()` anyway, but not
-- granting it at all means the refusal is never reached.
revoke all on function start_conversation(uuid, text) from public, anon;
revoke all on function delete_account() from public, anon;
grant execute on function start_conversation(uuid, text) to authenticated;
grant execute on function delete_account() to authenticated;
