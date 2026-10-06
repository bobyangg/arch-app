-- Which version of the terms each account accepted, and when.
--
-- The terms say they bind once they are "expressly accepted through the
-- acceptance process Arch provides". Onboarding is that process now, and this is
-- the record that it happened: one row per account per version, written by the
-- server's clock rather than the phone's.
--
-- A row per version, not a column on `accounts`, because the terms will change.
-- When they do, the question is not "has this person accepted" but "which
-- version, and when" -- and a column would answer that by overwriting the
-- previous answer.
--
-- Kept when an account is deleted, like the other records the privacy policy
-- lists as kept: it says what was agreed to, and nothing about the person.

create table if not exists terms_acceptances (
    account_id  uuid        not null references accounts(id),
    version     text        not null check (version ~ '^[0-9]+\.[0-9]+$'),
    accepted_at timestamptz not null default now(),
    primary key (account_id, version)
);

-- Written only through the function below, never read by the app.
alter table terms_acceptances enable row level security;

-- Accepting the same version twice keeps the first time. Onboarding calls this
-- when the box is ticked and again when the profile is saved, so a dropped
-- request at the first is caught by the second without moving the date.
create or replace function public.accept_terms(version text)
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
    if $1 is null or $1 !~ '^[0-9]+\.[0-9]+$' then
        raise exception 'unknown terms version' using errcode = '22023';
    end if;

    -- By constraint name: the parameter is also called `version`.
    insert into terms_acceptances (account_id, version)
    values (me, $1)
    on conflict on constraint terms_acceptances_pkey do nothing;
end;
$function$;

revoke all on function public.accept_terms(text) from public, anon;
grant execute on function public.accept_terms(text) to authenticated;
