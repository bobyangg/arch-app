-- Three signed-in functions stop being callable signed out, and two helpers get
-- a fixed search path. Both are the database advisor's, read before external
-- testing.
--
-- `dismiss_person`, `restore_person` and `register_push_token` were executable
-- by `anon`. Each already refuses a caller with no `auth.uid()`, so nothing was
-- reachable -- but a refusal inside the function is one line somebody can
-- delete, and the grant is the place to say it. `authenticated` keeps its own
-- grant.
--
-- `arch_free_place_changes` and `arch_next_refill` touch no tables, so a mutable
-- search path could not mislead them; pinned anyway so the advisor's list holds
-- only what is meant to be there.

revoke execute on function public.dismiss_person(uuid) from anon, public;
revoke execute on function public.restore_person(uuid) from anon, public;
revoke execute on function public.register_push_token(text, text) from anon, public;
grant execute on function public.dismiss_person(uuid) to authenticated;
grant execute on function public.restore_person(uuid) to authenticated;
grant execute on function public.register_push_token(text, text) to authenticated;

alter function private.arch_free_place_changes() set search_path = public;
alter function private.arch_next_refill(timestamptz) set search_path = public;
