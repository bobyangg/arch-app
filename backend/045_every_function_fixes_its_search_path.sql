-- Every function fixes its search path.
--
-- Supabase's security advisor flagged three functions that take their search
-- path from whoever calls them: `private.match_allowed` and
-- `private.match_milli` (037), and the trigger
-- `private.date_preferences_keep_in_step` (040, 042). A function like that can
-- be pointed at a look-alike table or operator by a caller able to create one.
-- Nobody here can -- neither `anon` nor `authenticated` may create anything in
-- any schema -- and all three run with the caller's own rights, not the
-- owner's, so there was nothing to gain from it. It is fixed anyway, so the
-- advisor's list stays empty and a later change cannot quietly make it matter.
--
-- `search_path = ''`: nothing is found by name outside `pg_catalog`. Every
-- table and function the two matcher functions use is already named with its
-- schema, and the trigger reads nothing but its own row.
--
-- **Nothing is lost by it.** 037 left the matcher functions without a search
-- path so that Postgres could fold them into the 9am run's query. It never
-- could: Postgres only inlines a SQL function whose body is a bare expression,
-- and `match_allowed` has subqueries and `match_milli` a `from`. `explain`
-- shows both called once per pair, with a search path or without.
--
-- In one transaction, with a check at the end that the 9am run's query still
-- runs: if anything here fails, nothing here is applied.

begin;

alter function private.match_allowed(match_people, match_people, date) set search_path = '';
alter function private.match_milli(match_people, match_people) set search_path = '';
alter function private.date_preferences_keep_in_step() set search_path = '';


-- ------------------------------------------------------------ the check
--
-- The candidate query reads both matcher functions for every pair. Run it on
-- the latest snapshot; a name that no longer resolves fails here.
do $check$
declare
    _night date := (select max(night) from match_people);
begin
    if _night is not null then
        perform count(*) from private.match_candidates(_night, 0);
    end if;
end;
$check$;

commit;
