-- Arch: does row-level security actually hold?
--
-- Paste the whole file into the Supabase SQL Editor and run it. It prints a table
-- of checks with PASS or FAIL against each.
--
-- **It ends in ROLLBACK, so nothing it creates survives.** The three people it
-- invents, their profiles, their answers and their pairing are all gone by the time
-- you read the results. Run it as often as you like, including against a database
-- with real rows in it.
--
-- The mechanism: the SQL Editor normally runs as an admin who bypasses RLS
-- entirely, which is why everything looks readable in the dashboard and proves
-- nothing. `set local role authenticated` plus a jwt claim makes the session behave
-- exactly like a signed-in client, which is the only way these policies get tested
-- before a real phone does it.

begin;

-- ------------------------------------------------------------------ the cast
--
--   A  is paired with B today
--   B  is the one doing the looking, in every check below
--   C  is a stranger to B: no pairing, no conversation

insert into auth.users (id, aud, role, email, created_at, updated_at)
values
    ('00000000-0000-4000-8000-0000000000a1', 'authenticated', 'authenticated',
     'a@rlstest.invalid', now(), now()),
    ('00000000-0000-4000-8000-0000000000b2', 'authenticated', 'authenticated',
     'b@rlstest.invalid', now(), now()),
    ('00000000-0000-4000-8000-0000000000c3', 'authenticated', 'authenticated',
     'c@rlstest.invalid', now(), now());

insert into accounts (id, apple_user_id) values
    ('00000000-0000-4000-8000-0000000000a1', 'apple-test-a'),
    ('00000000-0000-4000-8000-0000000000b2', 'apple-test-b'),
    ('00000000-0000-4000-8000-0000000000c3', 'apple-test-c');

insert into profiles (account_id, name, birthdate, gender, place_id,
                      coarse_lat, coarse_lon)
values
    ('00000000-0000-4000-8000-0000000000a1', 'Ada', '1996-01-01', 'woman',
     'bk-fort-greene', 40.69, -73.97),
    ('00000000-0000-4000-8000-0000000000b2', 'Ben', '1994-01-01', 'man',
     'bk-gowanus', 40.67, -73.99),
    ('00000000-0000-4000-8000-0000000000c3', 'Cal', '1995-01-01', 'man',
     'mn-east-village', 40.73, -73.98);

insert into questionnaire_answers (account_id, question_id, option_index)
values
    ('00000000-0000-4000-8000-0000000000a1', 'q1', 2),
    ('00000000-0000-4000-8000-0000000000a1', 'q9', 1),
    ('00000000-0000-4000-8000-0000000000b2', 'q1', 0);

-- A and B are in each other's roster. One row, both directions.
insert into pairings (night, lo_account, hi_account, score)
values ((now() at time zone 'America/New_York')::date,
        least('00000000-0000-4000-8000-0000000000a1'::uuid,
              '00000000-0000-4000-8000-0000000000b2'::uuid),
        greatest('00000000-0000-4000-8000-0000000000a1'::uuid,
                 '00000000-0000-4000-8000-0000000000b2'::uuid),
        11.4);

-- A has dismissed B. B must never be able to find that out.
insert into dismissals (account_id, other_account_id, night)
values ('00000000-0000-4000-8000-0000000000a1',
        '00000000-0000-4000-8000-0000000000b2',
        (now() at time zone 'America/New_York')::date);

-- A has blocked C, and reported them.
insert into blocks (blocker_id, blocked_id)
values ('00000000-0000-4000-8000-0000000000a1',
        '00000000-0000-4000-8000-0000000000c3');

insert into reports (reporter_id, reported_id, reason)
values ('00000000-0000-4000-8000-0000000000a1',
        '00000000-0000-4000-8000-0000000000c3', 'abuse');

insert into device_bits (device_hash, banned) values ('test-device-hash', true);


-- ----------------------------------------------------------------- the results

create temp table rls_results (
    ord      serial,
    check_it text,
    expected bigint,
    actual   bigint
) on commit drop;

-- The temp table belongs to the admin running this; the checks below run as a
-- signed-in user, who needs to be able to write their findings into it.
grant all on rls_results to authenticated;
grant usage, select on sequence rls_results_ord_seq to authenticated;


-- ------------------------------------------------------- now behave like a client

set local role authenticated;
set local request.jwt.claims to
    '{"sub":"00000000-0000-4000-8000-0000000000b2","role":"authenticated"}';

-- **The one that matters most.** The questionnaire works because people answer it
-- honestly, and they answer it honestly because it is shown to nobody.
insert into rls_results (check_it, expected, actual)
select 'B cannot read A questionnaire answers', 0, count(*)
from questionnaire_answers
where account_id = '00000000-0000-4000-8000-0000000000a1';

insert into rls_results (check_it, expected, actual)
select 'B can read own questionnaire answers', 1, count(*)
from questionnaire_answers
where account_id = '00000000-0000-4000-8000-0000000000b2';

insert into rls_results (check_it, expected, actual)
select 'B can see A profile while paired', 1, count(*)
from profiles where account_id = '00000000-0000-4000-8000-0000000000a1';

insert into rls_results (check_it, expected, actual)
select 'B cannot see C profile, a stranger', 0, count(*)
from profiles where account_id = '00000000-0000-4000-8000-0000000000c3';

-- Being dismissed is never discoverable, in either direction.
insert into rls_results (check_it, expected, actual)
select 'B cannot read the dismissal against them', 0, count(*)
from dismissals;

insert into rls_results (check_it, expected, actual)
select 'B cannot read A blocks', 0, count(*)
from blocks;

insert into rls_results (check_it, expected, actual)
select 'B cannot read any reports', 0, count(*)
from reports;

insert into rls_results (check_it, expected, actual)
select 'B cannot read device bits', 0, count(*)
from device_bits;

insert into rls_results (check_it, expected, actual)
select 'B sees only their own pairings', 1, count(*)
from pairings;

insert into rls_results (check_it, expected, actual)
select 'B cannot see C in the profiles view', 0, count(*)
from visible_profiles where account_id = '00000000-0000-4000-8000-0000000000c3';


-- ------------------------------------------------- writes that must be refused
--
-- A refusal arrives as an exception, so each one is attempted inside its own block
-- that catches it. A silent success here is the failure.

do $$
declare
    n bigint;
begin
    begin
        insert into pairings (night, lo_account, hi_account)
        values (current_date,
                '00000000-0000-4000-8000-0000000000b2',
                '00000000-0000-4000-8000-0000000000c3');
        -- RLS refuses this as a policy violation. If it lands, anybody could put
        -- themselves in any roster, and mutual pairing would mean nothing.
        insert into rls_results (check_it, expected, actual)
        values ('B cannot write their own pairing', 0, 1);
    exception when others then
        insert into rls_results (check_it, expected, actual)
        values ('B cannot write their own pairing', 0, 0);
    end;

    begin
        insert into blocks (blocker_id, blocked_id)
        values ('00000000-0000-4000-8000-0000000000a1',
                '00000000-0000-4000-8000-0000000000c3');
        insert into rls_results (check_it, expected, actual)
        values ('B cannot block on behalf of A', 0, 1);
    exception when others then
        insert into rls_results (check_it, expected, actual)
        values ('B cannot block on behalf of A', 0, 0);
    end;

    begin
        update profiles set name = 'Not Ada'
        where account_id = '00000000-0000-4000-8000-0000000000a1';
        get diagnostics n = row_count;
        insert into rls_results (check_it, expected, actual)
        values ('B cannot edit A profile', 0, n);
    exception when others then
        insert into rls_results (check_it, expected, actual)
        values ('B cannot edit A profile', 0, 0);
    end;

    begin
        -- Not in B's roster, so the guard inside the function should refuse it
        -- regardless of what RLS would have allowed.
        perform start_conversation('00000000-0000-4000-8000-0000000000c3', 'hello');
        insert into rls_results (check_it, expected, actual)
        values ('B cannot message a stranger', 0, 1);
    exception when others then
        insert into rls_results (check_it, expected, actual)
        values ('B cannot message a stranger', 0, 0);
    end;
end;
$$;

reset role;


-- ------------------------------------------------------------------- the verdict

select
    ord as "#",
    check_it as "check",
    expected as "want",
    actual as "got",
    case when expected = actual then 'PASS' else '>>> FAIL <<<' end as result
from rls_results
order by ord;

select
    count(*) filter (where expected = actual) || ' of ' || count(*) || ' passed'
        as summary,
    case when count(*) filter (where expected <> actual) = 0
         then 'Row-level security is doing what the design promises.'
         else 'Something is readable that should not be. Do not ship this.'
    end as verdict
from rls_results;

-- Nothing above survives.
rollback;
