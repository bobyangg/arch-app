-- A plan sent twice replaces the first.
--
-- Sharing the same plan to the same person again -- every stop, time, place
-- and length the same -- used to leave two identical cards in the thread. The
-- app now asks first ("You already sent this plan to Hana"), and if you send it
-- again, the earlier card is removed so only the newest shows.
--
-- Removing a message was not possible: messages have no delete policy, and that
-- stays true. `unsend_plan` is the one narrow way, and it refuses anything but:
--
--   * a message **you** sent,
--   * that carries a plan (stops), not words, an answer or a cancellation,
--   * that nobody has said "I'm in" to, and nobody has cancelled.
--
-- An answered plan is history both people acted on -- the app does not offer to
-- resend it -- and words are never unsendable. A notification already delivered
-- for the first copy cannot be called back; there is nothing to call it with.
--
-- Not read by the SQL lint: `messages.plan` is added in 024, which it does not
-- read -- the same reason 031 and 033 are not linted.

begin;

create or replace function public.unsend_plan(target uuid)
returns boolean
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

    delete from messages m
     where m.id = target
       and m.sender_id = me
       and m.plan is not null
       and m.plan ? 'stops'
       and not exists (
           select 1 from messages a
            where a.conversation_id = m.conversation_id
              and a.plan ->> 'answering' = m.id::text)
       and not exists (
           select 1 from messages c
            where c.conversation_id = m.conversation_id
              and c.plan ->> 'cancelling' = m.id::text);

    return found;
end;
$function$;

revoke all on function public.unsend_plan(uuid) from public, anon;
grant execute on function public.unsend_plan(uuid) to authenticated;

commit;
