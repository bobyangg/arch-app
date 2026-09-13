-- Arch: does row-level security actually hold?
--
-- Paste into the Supabase SQL Editor and run. It prints a PASS/FAIL table.
--
-- **It ends in ROLLBACK, so nothing it creates survives.** The three people it
-- invents, their profiles, answers, photos, pairing and the results table are all
-- gone by the time you read the output. Safe against a database with real rows in
-- it, as often as you like.
--
-- The mechanism: the SQL Editor normally runs as an admin who bypasses RLS
-- entirely, which is why every table looks readable in the dashboard and why that
-- tells you nothing. `set local role authenticated` plus a jwt claim makes the
-- session behave like a signed-in client, which is the only way these policies get
-- tested before a real phone does it.
--
-- This is not a formality. Run against the live database, it found a genuine leak:
-- the `arch_*` helpers were in the `public` schema, which made every one of them a
-- PostgREST RPC endpoint, and `arch_blocked(a, b)` would answer for any two
-- accounts. The policies were all correct; the side door was open. Check 15 is that
-- bug, kept as a regression test.
--
-- Results go in an ordinary table rather than a temporary one: `pg_temp` is not on
-- the search path once the session switches role, so the checks could not write
-- their findings into a temp table. An ordinary table inside a transaction that
-- rolls back is just as temporary and has no such problem.

begin;

drop table if exists rls_results;
create table rls_results (ord int, check_it text, expected bigint, actual bigint);
grant all on rls_results to authenticated;

-- ------------------------------------------------------------------ the cast
--   A  is paired with B today, and has a conversation with them
--   B  does all the looking below
--   C  is a stranger to B: no pairing, no conversation

insert into auth.users (id, aud, role, email, created_at, updated_at) values
 ('00000000-0000-4000-8000-0000000000a1','authenticated','authenticated','a@rlstest.invalid',now(),now()),
 ('00000000-0000-4000-8000-0000000000b2','authenticated','authenticated','b@rlstest.invalid',now(),now()),
 ('00000000-0000-4000-8000-0000000000c3','authenticated','authenticated','c@rlstest.invalid',now(),now());

insert into accounts (id, apple_user_id) values
 ('00000000-0000-4000-8000-0000000000a1','apple-test-a'),
 ('00000000-0000-4000-8000-0000000000b2','apple-test-b'),
 ('00000000-0000-4000-8000-0000000000c3','apple-test-c');

insert into profiles (account_id,name,birthdate,gender,place_id,coarse_lat,coarse_lon) values
 ('00000000-0000-4000-8000-0000000000a1','Ada','1996-01-01','woman','bk-fort-greene',40.69,-73.97),
 ('00000000-0000-4000-8000-0000000000b2','Ben','1994-01-01','man','bk-gowanus',40.67,-73.99),
 ('00000000-0000-4000-8000-0000000000c3','Cal','1995-01-01','man','mn-east-village',40.73,-73.98);

-- A has one approved photo and one still in moderation. Only the approved one is
-- anybody else's business.
insert into photos (account_id, position, storage_path, state) values
 ('00000000-0000-4000-8000-0000000000a1',0,'a/0.jpg','approved'),
 ('00000000-0000-4000-8000-0000000000a1',1,'a/1.jpg','pending'),
 ('00000000-0000-4000-8000-0000000000c3',0,'c/0.jpg','approved');

insert into profile_prompts (account_id, position, prompt_key, answer) values
 ('00000000-0000-4000-8000-0000000000a1',0,'p-twice','A book I read twice.');

insert into questionnaire_answers (account_id,question_id,option_index) values
 ('00000000-0000-4000-8000-0000000000a1','q1',2),
 ('00000000-0000-4000-8000-0000000000a1','q9',1),
 ('00000000-0000-4000-8000-0000000000b2','q1',0);

insert into pairings (night, lo_account, hi_account, score) values
 ((now() at time zone 'America/New_York')::date,
  least('00000000-0000-4000-8000-0000000000a1'::uuid,'00000000-0000-4000-8000-0000000000b2'::uuid),
  greatest('00000000-0000-4000-8000-0000000000a1'::uuid,'00000000-0000-4000-8000-0000000000b2'::uuid), 11.4);

-- A has blocked C, and reported them.
insert into blocks (blocker_id, blocked_id) values
 ('00000000-0000-4000-8000-0000000000a1','00000000-0000-4000-8000-0000000000c3');
insert into reports (reporter_id, reported_id, reason) values
 ('00000000-0000-4000-8000-0000000000a1','00000000-0000-4000-8000-0000000000c3','abuse');

insert into device_bits (device_hash, banned) values ('test-device-hash', true);

insert into conversations (lo_account, hi_account, state, opened_by, last_message_at) values
 (least('00000000-0000-4000-8000-0000000000a1'::uuid,'00000000-0000-4000-8000-0000000000b2'::uuid),
  greatest('00000000-0000-4000-8000-0000000000a1'::uuid,'00000000-0000-4000-8000-0000000000b2'::uuid),
  'open','00000000-0000-4000-8000-0000000000a1', now());
insert into messages (conversation_id, sender_id, body)
 select id,'00000000-0000-4000-8000-0000000000a1','hello' from conversations limit 1;


-- ------------------------------------------------------- now behave like a client

set local role authenticated;
set local request.jwt.claims to
    '{"sub":"00000000-0000-4000-8000-0000000000b2","role":"authenticated"}';

-- **The one that matters most.** The questionnaire works because people answer it
-- honestly, and they answer it honestly because it is shown to nobody.
insert into rls_results select 1,'B cannot read A questionnaire answers',0,count(*) from questionnaire_answers where account_id='00000000-0000-4000-8000-0000000000a1';
insert into rls_results select 2,'B can read own questionnaire answers',1,count(*) from questionnaire_answers where account_id='00000000-0000-4000-8000-0000000000b2';
insert into rls_results select 3,'B can see A profile while paired',1,count(*) from profiles where account_id='00000000-0000-4000-8000-0000000000a1';
insert into rls_results select 4,'B cannot see C profile (stranger)',0,count(*) from profiles where account_id='00000000-0000-4000-8000-0000000000c3';
insert into rls_results select 5,'B cannot read A blocks',0,count(*) from blocks;
insert into rls_results select 6,'B cannot read any reports',0,count(*) from reports;
insert into rls_results select 7,'B cannot read device bits',0,count(*) from device_bits;
insert into rls_results select 8,'B sees only their own pairings',1,count(*) from pairings;
insert into rls_results select 9,'B reads messages in their own thread',1,count(*) from messages;
insert into rls_results select 10,'B sees A approved photo only, not pending',1,count(*) from photos where account_id='00000000-0000-4000-8000-0000000000a1';
insert into rls_results select 11,'B cannot see C photos (stranger)',0,count(*) from photos where account_id='00000000-0000-4000-8000-0000000000c3';
insert into rls_results select 12,'B can read A prompts while paired',1,count(*) from profile_prompts;
insert into rls_results select 13,'B can see A in profiles view',1,count(*) from visible_profiles where account_id='00000000-0000-4000-8000-0000000000a1';
insert into rls_results select 14,'B cannot see C in profiles view',0,count(*) from visible_profiles where account_id='00000000-0000-4000-8000-0000000000c3';


-- ------------------------------------------------- writes that must be refused
--
-- A refusal arrives as an exception, so each is attempted inside its own block
-- that catches it. A silent success here is the failure.

do $$
begin
  -- The regression test for the leak this file found. Unqualified, because that is
  -- the name PostgREST would have exposed; it must no longer resolve at all.
  begin
    perform arch_blocked('00000000-0000-4000-8000-0000000000a1','00000000-0000-4000-8000-0000000000c3');
    insert into rls_results values (15,'no public arch_blocked to probe with',0,1);
  exception when others then
    insert into rls_results values (15,'no public arch_blocked to probe with',0,0);
  end;

  begin
    insert into pairings (night, lo_account, hi_account)
    values (current_date,'00000000-0000-4000-8000-0000000000b2','00000000-0000-4000-8000-0000000000c3');
    insert into rls_results values (16,'B cannot write their own pairing',0,1);
  exception when others then
    insert into rls_results values (16,'B cannot write their own pairing',0,0);
  end;

  begin
    perform start_conversation('00000000-0000-4000-8000-0000000000c3','hello');
    insert into rls_results values (17,'B cannot message a stranger',0,1);
  exception when others then
    insert into rls_results values (17,'B cannot message a stranger',0,0);
  end;

  begin
    insert into photos (account_id, position, storage_path)
    values ('00000000-0000-4000-8000-0000000000a1',3,'not-yours.jpg');
    insert into rls_results values (18,'B cannot add a photo to A profile',0,1);
  exception when others then
    insert into rls_results values (18,'B cannot add a photo to A profile',0,0);
  end;
end;
$$;

reset role;


-- ------------------------------------------------------------------- the verdict
--
-- One result set with the total as its last row: the SQL Editor shows only the
-- last statement's output, so a separate summary query would hide the checks it is
-- summarising.

select ord as "#", check_it as "check", expected::text as want, actual::text as got,
       case when expected=actual then 'PASS' else '>>> FAIL <<<' end as result
from rls_results
union all
select 99,
       (select count(*) filter (where expected=actual)||' of '||count(*)||' passed' from rls_results),
       '', '',
       (select case when count(*) filter (where expected<>actual)=0
                    then 'ALL PASS -- RLS does what the design promises'
                    else 'SOMETHING IS READABLE THAT SHOULD NOT BE' end
        from rls_results)
order by 1;

-- Nothing above survives, the results table included.
rollback;
