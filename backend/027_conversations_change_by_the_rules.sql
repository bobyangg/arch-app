-- Three loose ends, all about who may change what.
--
-- 1. **A conversation's state changes only by the rules.** `conversations_update_mine`
--    let either person in a conversation write any column of it. The app only ever
--    sends two changes -- accepting a request, and leaving -- but anybody holding a
--    session could send others: reopen a conversation the other person had left,
--    and carry on writing to them; accept their own request; rewrite who opened it
--    or when. On a dating app the first of those is the one that matters. A guard
--    on the table now allows, from the app, exactly the two changes it makes:
--
--      request -> open    by the person who did not open it (accepting)
--      anything -> ended  by either person (leaving, blocking, deleting)
--
--    and nothing else -- no other column, no other move. The server's own functions
--    (`start_conversation`, `delete_account`) run as their owner rather than as the
--    caller, and are not limited by it: reopening after a new introduction (025)
--    stays possible, because it is the server deciding, not a participant.
--
--    A guard rather than replacing the PATCHes with functions, so every build
--    already installed keeps working: its accept and leave are exactly the two
--    changes allowed.
--
-- 2. **A reply moves the conversation.** `last_message_at` was written by
--    `start_conversation` and never again, so a thread with a reply an hour ago
--    sorted and dated by its first message. A trigger on `messages` now keeps it.
--
-- 3. **Coming back clears "deleted".** `delete_account` stamps `deleted_at` and
--    keeps the row, and signing in again with the same Apple ID lands on that row
--    -- which is right -- but nothing cleared the stamp. Three accounts that deleted
--    and came back were still marked deleted while in daily use. An account is
--    deleted until its owner makes a profile again; creating one now clears it.

-- 1 ------------------------------------------------------------------------------

create or replace function private.guard_conversation_change()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
    -- Only calls straight from the app are held to this. A security definer
    -- function runs as its owner, so `current_user` is not `authenticated` there.
    if current_user <> 'authenticated' then
        return new;
    end if;

    if new.id              is distinct from old.id
       or new.lo_account   is distinct from old.lo_account
       or new.hi_account   is distinct from old.hi_account
       or new.opened_by    is distinct from old.opened_by
       or new.created_at   is distinct from old.created_at
       or new.last_message_at is distinct from old.last_message_at then
        raise exception 'only the state of a conversation can be changed' using errcode = '42501';
    end if;

    if new.state is distinct from old.state then
        if new.state = 'ended' then
            return new;
        end if;
        if old.state = 'request' and new.state = 'open' and auth.uid() is distinct from old.opened_by then
            return new;
        end if;
        raise exception 'that change is not yours to make' using errcode = '42501';
    end if;

    return new;
end;
$function$;

revoke all on function private.guard_conversation_change() from public, anon, authenticated;

drop trigger if exists conversations_guard on conversations;
create trigger conversations_guard
    before update on conversations
    for each row execute function private.guard_conversation_change();

-- 2 ------------------------------------------------------------------------------

create or replace function private.touch_conversation()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
    update conversations
       set last_message_at = greatest(coalesce(last_message_at, new.created_at), new.created_at)
     where id = new.conversation_id;
    return new;
end;
$function$;

revoke all on function private.touch_conversation() from public, anon, authenticated;

drop trigger if exists messages_touch_conversation on messages;
create trigger messages_touch_conversation
    after insert on messages
    for each row execute function private.touch_conversation();

update conversations c
   set last_message_at = m.newest
  from (select conversation_id, max(created_at) as newest from messages group by conversation_id) m
 where m.conversation_id = c.id
   and c.last_message_at is distinct from m.newest;

-- 3 ------------------------------------------------------------------------------

create or replace function private.profile_means_not_deleted()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
    update accounts set deleted_at = null
     where id = new.account_id and deleted_at is not null;
    return new;
end;
$function$;

revoke all on function private.profile_means_not_deleted() from public, anon, authenticated;

drop trigger if exists profiles_clear_deleted on profiles;
create trigger profiles_clear_deleted
    after insert on profiles
    for each row execute function private.profile_means_not_deleted();

-- The three who came back before this existed.
update accounts a set deleted_at = null
 where a.deleted_at is not null
   and exists (select 1 from profiles p where p.account_id = a.id);
