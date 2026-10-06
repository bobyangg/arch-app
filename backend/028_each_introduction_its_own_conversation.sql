-- Each introduction starts its own conversation; deleting is a fresh start;
-- blocking ends the conversation.
--
-- **A new introduction, a new conversation.** `conversations` allowed one row per
-- pair, ever, so two people introduced a second time were handed their first
-- conversation back. The app opened it, and it said "ended". 025 reopened that row
-- when somebody wrote, history and all -- which made it answerable, and also meant
-- the second introduction began with everything said in the first. Now a pair may
-- have any number of ended conversations and at most one live one (a partial
-- unique index), and writing after a new introduction starts a new, empty
-- conversation. The old one stays where it was, ended, in both people's lists. This
-- replaces 025's reopening; nothing reopens any more.
--
-- **Deleting your account is a fresh start.** `delete_account` keeps the account row
-- (so a ban cannot be escaped by deleting), and signing in again with the same
-- Apple ID lands on it -- so every conversation from before the deletion came back
-- with it. The privacy policy says deleting ends your conversations and that the
-- messages stay with the person you sent them to; it does not say they stay with
-- you. `accounts.fresh_since` is stamped at deletion and never cleared, and
-- conversations from before it are no longer readable by that account: not in the
-- list, not their messages, not in a data export. The other person keeps them.
--
-- **Blocking ends the conversation, on the server.** Blocks were checked when a
-- conversation started and never after, and the app's block ended the conversation
-- by looking for it in a list it had just emptied -- so it never did. A blocked
-- person in an open conversation could go on writing. A trigger on `blocks` now
-- ends every live conversation between the two, the same state leaving writes, so
-- neither side can tell a block from a leave. Live conversations that already sit
-- under a block are ended below.

-- A pair: many conversations, one live -------------------------------------------

alter table conversations drop constraint if exists conversations_lo_account_hi_account_key;

create unique index if not exists conversations_one_live_per_pair
    on conversations (lo_account, hi_account)
    where state <> 'ended';

create index if not exists conversations_pair on conversations (lo_account, hi_account);

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

    -- The live conversation if there is one, otherwise a new one. An ended
    -- conversation is never written into: it belongs to an earlier introduction.
    insert into conversations as c (lo_account, hi_account, state, opened_by, last_message_at)
    values (lo, hi, 'request', me, now())
    on conflict (lo_account, hi_account) where state <> 'ended' do update
        set last_message_at = now()
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

-- Deleting is a fresh start ------------------------------------------------------

alter table accounts add column if not exists fresh_since timestamptz;

comment on column accounts.fresh_since is
    'Set when the account is deleted, never cleared. Conversations created before it are not readable by this account.';

create or replace function private.arch_fresh_since(_account uuid)
returns timestamptz
language sql
stable
security definer
set search_path to 'public'
as $function$
    select coalesce((select a.fresh_since from accounts a where a.id = _account), '-infinity'::timestamptz)
$function$;

revoke all on function private.arch_fresh_since(uuid) from public, anon;
grant execute on function private.arch_fresh_since(uuid) to authenticated;

alter policy conversations_mine on conversations
    using (((select auth.uid()) in (lo_account, hi_account))
           and created_at >= private.arch_fresh_since((select auth.uid())));

create or replace function private.arch_in_thread(conversation uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
    select exists (
        select 1 from conversations c
        where c.id = conversation
          and auth.uid() in (c.lo_account, c.hi_account)
          and c.created_at >= private.arch_fresh_since(auth.uid())
    );
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
    -- nothing this function does is a moderator's decision. `fresh_since` is
    -- never cleared: coming back is a new start, not a restore.
    update accounts
       set deleted_at = now(),
           fresh_since = now(),
           apple_email = null,
           apple_name = null
     where id = me;

    return query select true;
end;
$function$;

create or replace function private.export_payload(_account uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
    select jsonb_build_object(
        'exported_at', now(),
        'account', (
            select jsonb_build_object('created_at', a.created_at, 'email', a.apple_email)
            from accounts a where a.id = _account
        ),
        'profile', (
            select jsonb_build_object(
                'name', p.name, 'birthdate', p.birthdate, 'gender', p.gender,
                'pronouns', p.pronouns, 'place', p.place_id,
                'height_cm', p.height_cm, 'work', p.work,
                'prompts', (select coalesce(jsonb_agg(jsonb_build_object(
                        'question', pr.prompt_key, 'answer', pr.answer)
                        order by pr.position), '[]'::jsonb)
                    from profile_prompts pr where pr.account_id = _account),
                'interests', (select coalesce(jsonb_agg(i.text order by i.position), '[]'::jsonb)
                    from profile_interests i where i.account_id = _account)
            )
            from profiles p where p.account_id = _account
        ),
        -- Your own answers, which nobody else has ever been able to see.
        'questionnaire', (
            select coalesce(jsonb_object_agg(q.question_id, q.option_index), '{}'::jsonb)
            from questionnaire_answers q where q.account_id = _account
        ),
        'settings', (
            select jsonb_build_object(
                'seeking', d.seeking, 'distance_miles', d.distance_miles,
                'min_age', d.min_age, 'max_age', d.max_age,
                'paused', d.paused, 'notify_messages', d.notify_messages)
            from discovery_settings d where d.account_id = _account
        ),
        -- Since the account was last deleted, if it ever was: a fresh start
        -- exports nothing from before it.
        'conversations', (
            select coalesce(jsonb_agg(c.payload order by c.started), '[]'::jsonb)
            from (
                select conv.created_at as started,
                    jsonb_build_object(
                        'with', (select pr.name from profiles pr
                                  where pr.account_id = case when conv.lo_account = _account
                                        then conv.hi_account else conv.lo_account end),
                        'state', conv.state,
                        'messages', (select coalesce(jsonb_agg(jsonb_build_object(
                                'at', m.created_at,
                                'from', case when m.sender_id = _account then 'you' else 'them' end,
                                'body', m.body) order by m.created_at), '[]'::jsonb)
                            from messages m where m.conversation_id = conv.id)
                    ) as payload
                from conversations conv
                where _account in (conv.lo_account, conv.hi_account)
                  and conv.created_at >= private.arch_fresh_since(_account)
            ) c
        ),
        -- Who has been in your roster and when. Names and nights, no score.
        'roster_history', (
            select coalesce(jsonb_agg(jsonb_build_object(
                'night', pg.night,
                'name', (select pr.name from profiles pr where pr.account_id = pg.other))
                order by pg.night desc), '[]'::jsonb)
            from (
                select night, case when lo_account = _account then hi_account
                                   else lo_account end as other
                from pairings where _account in (lo_account, hi_account)
            ) pg
        ),
        -- Blocks **you** placed. Never ones placed on you.
        'people_you_blocked', (
            select coalesce(jsonb_agg(jsonb_build_object('at', b.created_at)), '[]'::jsonb)
            from blocks b where b.blocker_id = _account
        ),
        'photos', (
            select coalesce(jsonb_agg(jsonb_build_object(
                'file', 'photos/' || (ph.position + 1) || '.jpg',
                'state', ph.state, 'added', ph.created_at) order by ph.position), '[]'::jsonb)
            from photos ph where ph.account_id = _account
        )
    );
$function$;

-- Blocking ends the conversation -------------------------------------------------

create or replace function private.block_ends_conversations()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
    update conversations
       set state = 'ended'
     where lo_account = least(new.blocker_id, new.blocked_id)
       and hi_account = greatest(new.blocker_id, new.blocked_id)
       and state <> 'ended';
    return new;
end;
$function$;

revoke all on function private.block_ends_conversations() from public, anon, authenticated;

drop trigger if exists blocks_end_conversations on blocks;
create trigger blocks_end_conversations
    after insert on blocks
    for each row execute function private.block_ends_conversations();

update conversations c
   set state = 'ended'
 where c.state <> 'ended'
   and exists (select 1 from blocks b
                where least(b.blocker_id, b.blocked_id) = c.lo_account
                  and greatest(b.blocker_id, b.blocked_id) = c.hi_account);
