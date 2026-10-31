-- People who are already talking are not introduced again.
--
-- Two people who start a conversation stay in it for as long as they like, but
-- the matcher only remembered that they had *met*: `encounters` keeps the last
-- night they were paired, and the seven-night cooldown holds the pair off for
-- a week after it. A conversation outlives that easily, so a week after their
-- introduction the 9am run was free to put two people who were still writing
-- to each other back in each other's Daily -- it did, ten times between the
-- 27th and the 29th of October. It cost each of them a slot that morning, and
-- it looked like the app had forgotten they were already talking.
--
-- So `private.match_allowed` now refuses a pair with a live conversation --
-- a request waiting for an answer, or open -- the same states
-- `private.arch_in_conversation` reads as "still running". It is the one pair
-- test, so the 9am run and an arrival's same-day matching (037, 038) both get
-- it.
--
-- **Ended conversations are unchanged.** 025 and 028 decided that two people
-- whose conversation ended may be introduced again once the cooldown has
-- passed, and that writing after the new introduction starts a new, empty
-- conversation. That still holds: this only stops a pairing nobody needs,
-- between two people who already have each other.
--
-- **What it costs.** The function is called once per pair (045 explains why
-- it was never folded into the query), and the new check is one more probe
-- per pair, on `conversations_one_live_per_pair` (028). It keeps 045's empty
-- search path -- `create or replace` would otherwise drop it -- so
-- `conversations` is named by schema like every other table in it. Both
-- callers are `security definer`, so the table's row security is not in the
-- way.
--
-- In one transaction, with a check at the end that the 9am run's query still
-- plans and runs: if anything here fails, nothing here is applied.

begin;

create or replace function private.match_allowed(pa match_people, pb match_people, _night date)
returns boolean
language sql
stable
set search_path = ''
as $function$
    select
        -- Orientation, both ways.
        pb.gender = any(pa.seeking) and pa.gender = any(pb.seeking)

        -- Age, both ways.
        and pb.age between pa.min_age and pa.max_age
        and pa.age between pb.min_age and pb.max_age

        -- Distance, both ways. **Not `least(radius)`** -- a slider at 100 reads
        -- "Anywhere" and means no filter at all on that side.
        and (pa.radius >= 100 or private.arch_miles(pa.lat, pa.lon, pb.lat, pb.lon) <= pa.radius)
        and (pb.radius >= 100 or private.arch_miles(pa.lat, pa.lon, pb.lat, pb.lon) <= pb.radius)

        -- The three requirement questions. All three must resolve, or a question
        -- that grew an option would silently stop filtering.
        and (select count(*) = 3 and bool_and(rc.allowed)
               from generate_subscripts(pa.req, 1) k
               join public.requirement_cells rc
                 on rc.question_id = 'q' || (13 + k)
                and rc.a = pa.req[k] and rc.b = pb.req[k])

        -- Blocks, either direction, never saying which.
        and not exists (
            select 1 from public.blocks bl
            where (bl.blocker_id = pa.account_id and bl.blocked_id = pb.account_id)
               or (bl.blocker_id = pb.account_id and bl.blocked_id = pa.account_id))

        -- Already met recently.
        and not exists (
            select 1 from public.encounters en
            where en.account_id = pa.account_id
              and en.other_account_id = pb.account_id
              and en.last_night > _night - private.match_cooldown())

        -- Already talking. `least`/`greatest` rather than trusting `pa` to be the
        -- lower id, so the test cannot quietly stop working for a caller that
        -- passes them the other way round.
        and not exists (
            select 1 from public.conversations c
            where c.lo_account = least(pa.account_id, pb.account_id)
              and c.hi_account = greatest(pa.account_id, pb.account_id)
              and c.state <> 'ended')
$function$;

revoke all on function private.match_allowed(match_people, match_people, date) from public, anon, authenticated;


-- ------------------------------------------------------------ the check
--
-- The 9am run's candidate query runs against the latest snapshot, and no pair
-- it returns has a live conversation.
do $check$
declare
    _night date := (select max(night) from match_people);
    _live  integer;
begin
    if _night is null then
        return;
    end if;

    select count(*) into _live
      from private.match_candidates(_night, 0) mc
      join public.conversations c
        on c.lo_account = least(mc.a_id, mc.b_id)
       and c.hi_account = greatest(mc.a_id, mc.b_id)
       and c.state <> 'ended';

    if _live > 0 then
        raise exception '046: % candidate pairs on % are already talking', _live, _night;
    end if;
end;
$check$;

commit;
