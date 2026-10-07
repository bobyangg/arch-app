-- `delete_account`, with everything both branches added to it.
--
-- Two branches each redefined it in full on the same day: 026 and 028 (copying
-- the introductions into analytics first, emptying dismissals, location changes,
-- device keys, queued notifications and export requests, and stamping
-- `fresh_since`), and 029 (emptying `date_preferences`). 029 was written from the
-- older function and applied after 028, so the live function lost all of 026 and
-- 028 and kept only 029's line. Each `create or replace` is the whole function,
-- so the last one applied wins outright.
--
-- This is the union, applied last. Whoever redefines `delete_account` next should
-- start from this file, not from an older one.

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

    -- First, while everything is still here: copy this person's introductions
    -- into the analytics record (026). A failure is logged, never fatal.
    begin
        perform analytics.record();
    exception when others then
        raise warning 'analytics.record() failed during delete_account: %', sqlerrm;
    end;

    -- Ended first, so deleting looks identical to blocking or leaving.
    update conversations
       set state = 'ended'
     where me in (lo_account, hi_account)
       and state <> 'ended';

    -- Out of every future roster before anything else is touched.
    delete from pairings where me in (lo_account, hi_account);
    delete from encounters where me in (account_id, other_account_id);
    delete from dismissals where me in (account_id, other_account_id);

    delete from questionnaire_answers where account_id = me;
    delete from date_preferences where account_id = me;
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

    -- Blocks they placed go; blocks placed *on* them stay, so that deleting an
    -- account is not a way to clear the record of having been blocked.
    delete from blocks where blocker_id = me;

    -- `status` is untouched: a moderator's decision outlives this function.
    -- `fresh_since` is never cleared: coming back is a new start, not a
    -- restore (028).
    update accounts
       set deleted_at = now(),
           fresh_since = now(),
           apple_email = null,
           apple_name = null
     where id = me;

    return query select true;
end;
$function$;

comment on function public.delete_account() is
    'Copies introductions to analytics, ends conversations (so deleting looks like leaving), empties every table of the account''s own data, keeps the accounts row so the Apple id stays claimed and moderation records attach, and stamps fresh_since. Start any future change from backend/030.';
