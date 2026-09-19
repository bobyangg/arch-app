-- Deleting your own account is not a ban, and treating it as one locked people out
-- of their own Apple ID forever.
--
-- `delete_account` set `status = 'removed'`. `register` refuses any sign-in where
-- the status is `removed`. Between them, deleting your account meant every future
-- sign-in with that Apple ID got a 403 -- permanently, with no route back from
-- inside the app. The first person to delete an account and come back hit it
-- immediately, which is how it was found.
--
-- **The two things `removed` was being asked to mean:**
--
--   * moderation removed you  -- must survive deletion, must refuse a return
--   * you deleted your account -- must not refuse anything
--
-- `status` is the moderation state and only the moderation state. It is set by
-- `tools/moderate.py`, which writes a `removals` row and *then* sets the status,
-- always both. `deleted_at` is a separate and orthogonal fact: whether this person
-- has ever emptied their account. Somebody can be active and have deleted once, and
-- after this change that is exactly what a returning person looks like.
--
-- **Nothing about the protection is given up.** The `accounts` row still survives
-- with the same id, so a `removals` row written before or after a deletion still
-- attaches to this person and `register` still refuses them on the status it set.
-- Blocks placed *on* them still survive. A device banned by moderation is still
-- refused by the DeviceCheck bit, before the account is ever looked at.
--
-- `deleted_at` is deliberately not added to the matcher's `status = 'active'` join:
-- somebody who deleted, came back and built a new profile is a real user again, and
-- filtering on it would quietly make them unmatchable forever -- the same class of
-- bug as this one, one layer down.

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

    -- `status` is untouched. A moderator's decision outlives this function, and
    -- nothing this function does is a moderator's decision.
    update accounts
       set deleted_at = now(),
           apple_email = null,
           apple_name = null
     where id = me;

    return query select true;
end;
$$;

comment on function delete_account is
    'Ends conversations first so that deleting looks identical to blocking or leaving. Keeps the accounts row so the Apple id stays claimed and any moderation record still attaches to it. Does not touch status: status is the moderation state, deleted_at is whether they emptied the account, and conflating the two refused returning people forever.';

-- The account this was found on: self-deleted, no moderation record, refused at
-- every sign-in since. Scoped to exactly that shape, so it can never revive
-- somebody moderation actually removed.
update accounts a
   set status = 'active'
 where a.status = 'removed'
   and a.deleted_at is not null
   and not exists (select 1 from removals r where r.account_id = a.id);
