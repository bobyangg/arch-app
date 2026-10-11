-- "Not for us": places a person never wants the Date planner to offer again,
-- and places taken off for everybody.
--
-- **hidden_places** is one person's. Tapping "Not for us" on a stop writes a
-- row; the planner never offers that place to them again, on any phone. Owner
-- only, like the questionnaire: what you hid is nobody else's business.
--
-- **place_blocklist** is everybody's, and only the team writes it, from the
-- dashboard -- there is no write policy, so no app can. When Apple Maps calls
-- something a park that is not (a corner, a parkette, a stage with nothing
-- on), adding its key here takes it out of every plan without an app release.
--
-- **private.place_hide_counts** is how to find what to add: the places hidden
-- most, by how many people. In `private`, so PostgREST does not serve it; read
-- it in the SQL Editor.
--
-- A place's key is the planner's id for it -- for Apple Maps,
-- "mk:<name>|<lat>|<lon>" to four places -- and its name is kept beside it so a
-- person can read their own list.

create table hidden_places (
    account_id      uuid not null references accounts(id) on delete cascade,
    place_key       text not null check (length(place_key) between 1 and 300),
    name            text not null check (length(name) between 1 and 200),
    hidden_at       timestamptz not null default now(),

    primary key (account_id, place_key)
);

alter table hidden_places enable row level security;

create policy hidden_places_own_read on hidden_places
    for select using (account_id = (select auth.uid()));
create policy hidden_places_own_insert on hidden_places
    for insert with check (account_id = (select auth.uid()));
-- An update, only because hiding a place you already hid is an upsert, and an
-- upsert that meets its own row is an update.
create policy hidden_places_own_update on hidden_places
    for update using (account_id = (select auth.uid()))
    with check (account_id = (select auth.uid()));
create policy hidden_places_own_delete on hidden_places
    for delete using (account_id = (select auth.uid()));

create table place_blocklist (
    place_key       text primary key check (length(place_key) between 1 and 300),
    name            text not null,
    reason          text,
    added_at        timestamptz not null default now()
);

alter table place_blocklist enable row level security;

-- Readable by anybody signed in, writable by nobody through the API.
create policy place_blocklist_read on place_blocklist
    for select using ((select auth.uid()) is not null);

create or replace view private.place_hide_counts as
    select place_key, min(name) as name, count(*) as hidden_by, max(hidden_at) as last_hidden
    from hidden_places
    group by place_key
    order by count(*) desc;

revoke all on private.place_hide_counts from public, anon, authenticated;


-- Deleting an account empties hidden_places too. 030's function, with one line
-- added beside date_preferences -- start any later change from here.

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
    delete from hidden_places where account_id = me;
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
    'Copies introductions to analytics, ends conversations (so deleting looks like leaving), empties every table of the account''s own data (hidden_places included), keeps the accounts row so the Apple id stays claimed and moderation records attach, and stamps fresh_since. Start any future change from backend/032.';
