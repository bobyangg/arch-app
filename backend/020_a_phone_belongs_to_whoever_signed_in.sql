-- A push token belongs to whoever is signed in on that phone now.
--
-- `push_tokens` is unique on `token`, and the client wrote it with a plain upsert
-- that named no conflict column -- so PostgREST merged on the primary key, which
-- the client never sends, and every upload was an insert. The first one landed.
-- Every later one for the same phone hit `push_tokens_token_key`, got a 409, and
-- the client threw the error away.
--
-- For one person on one phone that was merely wasteful. For two people on one
-- phone -- which is how this app has actually been tested, signing in and out of
-- accounts on the same device -- it meant the token stayed with whoever signed in
-- first. The second person never got a notification, and the first person's
-- messages went on arriving on a phone they were no longer signed in to.
--
-- It also could not have been fixed from the client. Reassigning the row means
-- updating one that belongs to another account, and `push_self` quite rightly
-- refuses that. So it is a function: it runs as the owner, takes the token for
-- the caller, and never lets the caller choose whose account it lands on.
--
-- Nothing had ever reached this table anyway -- the app only asked iOS for a
-- token at launch, and only when it was already signed in, which a bug in how
-- the session was read back made impossible. This is the half of that fix that
-- lives on the server.

create or replace function public.register_push_token(token text, environment text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
#variable_conflict use_column
declare
    me uuid := auth.uid();
begin
    if me is null then
        raise exception 'not signed in' using errcode = '28000';
    end if;
    -- The two hosts Apple runs. A sandbox token sent to production fails with
    -- BadDeviceToken, which the sender reads as "this device is gone" and
    -- deletes -- so a wrong label here is a token that vanishes on first use.
    if $2 not in ('sandbox', 'production') then
        raise exception 'unknown push environment' using errcode = '22023';
    end if;

    -- By constraint name, not `(token)`: the parameter is also called `token`,
    -- and a conflict target is parsed as an expression that can see it.
    insert into push_tokens (account_id, token, environment, updated_at)
    values (me, $1, $2, now())
    on conflict on constraint push_tokens_token_key do update
       set account_id     = excluded.account_id,
           environment    = excluded.environment,
           updated_at     = now(),
           last_failed_at = null,
           failure        = null;
end;
$function$;

revoke all on function public.register_push_token(text, text) from public;
grant execute on function public.register_push_token(text, text) to authenticated;
