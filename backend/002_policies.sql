-- Arch: row-level security.
--
-- The schema says what can be stored. This says who can read it, and it is the
-- half that keeps the product's promises. Every table is deny-by-default: RLS is
-- enabled with no permissive policy until one is written below.
--
-- The nightly matcher runs as `service_role`, which bypasses RLS entirely. That is
-- intended -- it has to read everybody's answers to pair anyone -- and it is why
-- the service key must never reach a client.
--
-- Two things here were learned by running it against a real database rather than
-- by reasoning about it, and both are worth knowing before editing this file.
--
-- **The helpers live in `private`, not `public`.** Anything in `public` is also a
-- PostgREST endpoint. These functions are SECURITY DEFINER, so they read blocks and
-- pairings with RLS switched off -- and while they sat in `public`,
-- `/rest/v1/rpc/arch_blocked?a=X&b=Y` was an oracle any signed-in user could ask
-- about any two accounts. The policies were correct and the side door was open.
-- A verified leak, not a theoretical one.
--
-- **`auth.uid()` is always wrapped in a scalar subquery.** Written bare it is
-- re-evaluated for every row scanned; as `(select auth.uid())` it is evaluated once.
-- On a table holding every account, that is the whole difference.

-- ------------------------------------------------------------------- helpers
--
-- All `security definer` so they can consult tables the caller cannot read.
-- Without that, a policy on `profiles` that checks `blocks` would recurse through
-- the policy on `blocks` and fail.
--
-- `authenticated` keeps EXECUTE because policy expressions are evaluated as the
-- querying user, and the policies would fail without it. What it does not keep is
-- a route to call them directly.

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

-- Has either person blocked the other? Direction does not matter: a block stops
-- the pair in both directions, and neither side is told which way it went.
create or replace function private.arch_blocked(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from blocks
        where (blocker_id = a and blocked_id = b)
           or (blocker_id = b and blocked_id = a)
    );
$$;

-- Are these two in each other's roster right now?
--
-- Reads the pair from `pairings`, where one row is both directions, so this cannot
-- disagree with itself. A dismissal ends the viewing right for the person who
-- dismissed; the other side keeps their slot and is never told.
create or replace function private.arch_paired_now(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from pairings p
        where p.night > current_date - interval '2 days'
          and ((p.lo_account = a and p.hi_account = b)
            or (p.lo_account = b and p.hi_account = a))
          and not exists (
              select 1 from dismissals d
              where d.night = p.night
                and d.account_id = a
                and d.other_account_id = b
          )
    );
$$;

-- Is there a conversation still running between them?
--
-- **'ended' is excluded deliberately.** Leaving, blocking and deleting all land on
-- 'ended', and all three must look the same from the other side. If a block took
-- the profile away and leaving did not, the difference would say which had
-- happened -- so an ended conversation takes the profile away in every case.
create or replace function private.arch_in_conversation(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from conversations c
        where c.state in ('request', 'open')
          and ((c.lo_account = a and c.hi_account = b)
            or (c.lo_account = b and c.hi_account = a))
    );
$$;

-- The single rule for seeing somebody's profile, photos, prompts and interests.
-- Inner calls are schema-qualified so that `search_path = public` keeps resolving
-- tables in public while the helpers still find each other.
create or replace function private.arch_can_see(subject uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select
        (select auth.uid()) = subject
        or (
            not private.arch_blocked((select auth.uid()), subject)
            and (private.arch_paired_now((select auth.uid()), subject)
                 or private.arch_in_conversation((select auth.uid()), subject))
        );
$$;

create or replace function private.arch_in_thread(conversation uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from conversations c
        where c.id = conversation
          and (select auth.uid()) in (c.lo_account, c.hi_account)
    );
$$;

revoke all on all functions in schema private from public;
grant execute on all functions in schema private to authenticated, service_role;


-- ------------------------------------------------------------------- accounts

alter table accounts enable row level security;

create policy accounts_self_read on accounts
    for select using (id = (select auth.uid()));
create policy accounts_self_update on accounts
    for update using (id = (select auth.uid()))
    with check (id = (select auth.uid()));
-- No insert policy: accounts are created by the signup edge function, which runs
-- with the service key after it has verified Apple's token and the App Attest
-- attestation. A client that could insert its own account row could pick its own
-- apple_user_id and inherit somebody else's ban.

alter table account_devices enable row level security;
create policy devices_self_read on account_devices
    for select using (account_id = (select auth.uid()));
-- Writes are server-side only: the attestation counter is a replay defence, and a
-- client that can set it can replay.

alter table device_bits enable row level security;
-- No policy at all, deliberately. These rows outlive accounts and are how a removed
-- user is recognised coming back; a client that could read them could test for its
-- own ban before deciding whether to bother, and one that could write them could
-- clear it. Supabase's linter flags this as "RLS enabled, no policy" -- that is the
-- intended state, not an oversight.


-- ------------------------------------------------------------------- profiles

alter table profiles enable row level security;

create policy profiles_visible on profiles
    for select using (private.arch_can_see(account_id));
create policy profiles_self_write on profiles
    for insert with check (account_id = (select auth.uid()));
create policy profiles_self_update on profiles
    for update using (account_id = (select auth.uid()))
    with check (account_id = (select auth.uid()));

-- Photos, prompts and interests all follow the profile, and all split their write
-- policies by command rather than using `for all`. A `for all` policy includes
-- SELECT, so it would be evaluated alongside the visibility policy on every single
-- read; reading your own rows is already the first branch there.

alter table photos enable row level security;
create policy photos_visible on photos
    for select using (
        -- Your own, at any state, so a rejection can be explained to you. Other
        -- people's only once approved: nothing pending is ever shown.
        (account_id = (select auth.uid()))
        or (state = 'approved' and private.arch_can_see(account_id))
    );
create policy photos_self_insert on photos
    for insert with check (account_id = (select auth.uid()));
create policy photos_self_update on photos
    for update using (account_id = (select auth.uid()))
    with check (account_id = (select auth.uid()));
create policy photos_self_delete on photos
    for delete using (account_id = (select auth.uid()));

alter table profile_prompts enable row level security;
create policy prompts_visible on profile_prompts
    for select using (private.arch_can_see(account_id));
create policy prompts_self_insert on profile_prompts
    for insert with check (account_id = (select auth.uid()));
create policy prompts_self_update on profile_prompts
    for update using (account_id = (select auth.uid()))
    with check (account_id = (select auth.uid()));
create policy prompts_self_delete on profile_prompts
    for delete using (account_id = (select auth.uid()));

alter table profile_interests enable row level security;
create policy interests_visible on profile_interests
    for select using (private.arch_can_see(account_id));
create policy interests_self_insert on profile_interests
    for insert with check (account_id = (select auth.uid()));
create policy interests_self_update on profile_interests
    for update using (account_id = (select auth.uid()))
    with check (account_id = (select auth.uid()));
create policy interests_self_delete on profile_interests
    for delete using (account_id = (select auth.uid()));


-- --------------------------------------------------- the answers nobody sees

alter table questionnaire_answers enable row level security;

-- **Owner only. There is no second policy and there should never be one.**
--
-- Not "owner and the people you match with", not "owner and a redacted version".
-- The questionnaire works because people answer it honestly, and they answer it
-- honestly because it is never shown. A single permissive policy added here later
-- would undo that quietly and nothing would visibly break.
--
-- The matcher reads this table as `service_role`, off the back of the API, and
-- returns pairings -- never answers.
create policy answers_owner_only on questionnaire_answers
    for all using (account_id = (select auth.uid()))
    with check (account_id = (select auth.uid()));


-- ------------------------------------------------------------------ discovery

alter table discovery_settings enable row level security;
create policy discovery_self on discovery_settings
    for all using (account_id = (select auth.uid()))
    with check (account_id = (select auth.uid()));

alter table subscriptions enable row level security;
create policy subscriptions_self_read on subscriptions
    for select using (account_id = (select auth.uid()));
-- Written only by the server, after Apple's receipt has been verified with Apple.


-- -------------------------------------------------------------------- pairing

alter table pairings enable row level security;

create policy pairings_mine on pairings
    for select using ((select auth.uid()) in (lo_account, hi_account));
-- Insert is the matcher's alone. A client that could write a pairing could put
-- itself in anybody's roster, which is the one thing mutual pairing exists to stop.
--
-- `score` is readable by this policy along with the rest of the row. The API layer
-- must not select it into any client response: Arch shows no percentages, no ranks
-- and no badges, and a number on the wire is a number that reaches a screen
-- eventually. `ArchBackend.roster()` names its columns for this reason.

alter table dismissals enable row level security;
create policy dismissals_own on dismissals
    for all using (account_id = (select auth.uid()))
    with check (account_id = (select auth.uid()));
-- Note the policy is on `account_id` only. The person dismissed cannot read the
-- row, cannot count the rows, and is never told. That is the whole point.

alter table encounters enable row level security;
create policy encounters_own on encounters
    for select using (account_id = (select auth.uid()));


-- --------------------------------------------------------------- conversations

alter table conversations enable row level security;

create policy conversations_mine on conversations
    for select using ((select auth.uid()) in (lo_account, hi_account));
create policy conversations_update_mine on conversations
    for update using ((select auth.uid()) in (lo_account, hi_account))
    with check ((select auth.uid()) in (lo_account, hi_account));

alter table messages enable row level security;

create policy messages_read on messages
    for select using (private.arch_in_thread(conversation_id));

create policy messages_send on messages
    for insert with check (
        sender_id = (select auth.uid())
        and private.arch_in_thread(conversation_id)
        -- An ended conversation takes no more messages. Enforced here rather than
        -- in the client, because the client is not a security boundary and the
        -- other person may have ended it for their own safety.
        and exists (
            select 1 from conversations c
            where c.id = conversation_id and c.state in ('request', 'open')
        )
    );

-- No update and no delete policy. Messages are not editable and not retractable:
-- an edited message is a different conversation from the one the other person
-- read, and a retractable one is a way to say something and take it back.

alter table push_tokens enable row level security;
create policy push_self on push_tokens
    for all using (account_id = (select auth.uid()))
    with check (account_id = (select auth.uid()));


-- --------------------------------------------------------------------- safety

alter table blocks enable row level security;

create policy blocks_own on blocks
    for select using (blocker_id = (select auth.uid()));
create policy blocks_create on blocks
    for insert with check (blocker_id = (select auth.uid()));
create policy blocks_remove on blocks
    for delete using (blocker_id = (select auth.uid()));
-- Only the blocker. Nobody can query whether they have been blocked, and nobody
-- can count how many times they have been.

alter table reports enable row level security;

create policy reports_create on reports
    for insert with check (reporter_id = (select auth.uid()));
-- Deliberately no select policy, not even for the reporter. Reporting is not a
-- ticket to track: the screen says it has been received and that is the end of the
-- reader's involvement. It also means nobody can probe whether somebody else has
-- been reported.

alter table removals enable row level security;
create policy removals_self on removals
    for select using (account_id = (select auth.uid()));

alter table appeals enable row level security;
create policy appeals_self_read on appeals
    for select using (
        exists (select 1 from removals r
                where r.id = removal_id and r.account_id = (select auth.uid()))
    );
create policy appeals_self_create on appeals
    for insert with check (
        exists (select 1 from removals r
                where r.id = removal_id and r.account_id = (select auth.uid()))
    );


-- ------------------------------------------------------------------- the view

-- What a client is allowed to receive for somebody else.
--
-- A view rather than a convention, because `select *` is what people write when
-- they are busy. Age is computed; birthdate does not leave the database. There is
-- no score column, no questionnaire join, and nothing about when they were last
-- seen.
create or replace view visible_profiles
with (security_invoker = true) as
select
    p.account_id,
    p.name,
    extract(year from age(p.birthdate))::int as age,
    p.gender,
    p.pronouns,
    p.place_id,
    p.height_cm,
    p.work
from profiles p;

comment on view visible_profiles is
    'The only shape a profile should leave the database in. No birthdate, no coordinates, no score, no questionnaire answers, no last-seen.';
