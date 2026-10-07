-- What somebody wants a date to be like, for the Date planner.
--
-- Five multiple-choice answers, asked the first time the planner is opened:
-- what a good first date sounds like, afternoon or evening, drinks, what to
-- spend, and whether to keep it walkable. The planner reads both people's
-- answers and plans around the two of them -- a stricter answer wins where one
-- is a rule (no drinks, walkable), and the rest are blended.
--
-- **Not the onboarding questionnaire, and not as private as it.**
-- `questionnaire_answers` is owner-only forever, because it decides who you
-- meet and only works if nobody ever sees it. These decide what a date with
-- somebody you are already talking to looks like, and the planner on *their*
-- phone needs yours to do that. So:
--
--   - you read and write your own;
--   - the people you have a conversation with (a request or open, the same set
--     the planner plans with) can read yours;
--   - nobody else can: not the Daily 5, not anybody you have blocked or who has
--     blocked you, and not anybody whose conversation with you has ended.
--
-- The app never shows another person's answers. A plan reflects them -- no bar
-- in it, nothing past walking distance -- and the reasons under each stop never
-- quote them. The intro says exactly this before the first question.
--
-- Text with a check rather than enums: five small sets that will be reworded and
-- extended, and an enum is a migration every time a choice is added. The values
-- are the raw values of the Swift enums in `DatePreferences.swift`.

create table date_preferences (
    account_id      uuid primary key references accounts(id) on delete cascade,
    style           text not null check (style in ('talk', 'doing', 'outside', 'night_out')),
    time_of_day     text not null check (time_of_day in ('afternoon', 'evening', 'either')),
    drinks          text not null check (drinks in ('yes', 'sometimes', 'no')),
    budget          text not null check (budget in ('low', 'middle', 'any')),
    distance        text not null check (distance in ('walkable', 'ride')),
    answered_at     timestamptz not null default now()
);

comment on table date_preferences is
    'Date planner answers. Readable by the owner and by people in a request or open conversation with them; never shown, only planned around.';

alter table date_preferences enable row level security;

create policy date_preferences_read on date_preferences
    for select using (
        account_id = (select auth.uid())
        or (
            not private.arch_blocked((select auth.uid()), account_id)
            and private.arch_in_conversation((select auth.uid()), account_id)
        )
    );

create policy date_preferences_self_insert on date_preferences
    for insert with check (account_id = (select auth.uid()));

create policy date_preferences_self_update on date_preferences
    for update using (account_id = (select auth.uid()))
    with check (account_id = (select auth.uid()));

create policy date_preferences_self_delete on date_preferences
    for delete using (account_id = (select auth.uid()));


-- **Deleting an account deletes these.** `delete_account` keeps the `accounts`
-- row on purpose (see 016), so `on delete cascade` above never fires for it, and
-- every table it should empty has to be named. This is 016's function with one
-- line added, beside the other set of answers.

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
    delete from date_preferences where account_id = me;
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
