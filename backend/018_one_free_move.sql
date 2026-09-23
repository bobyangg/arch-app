-- Where you say you are: free once, unlimited with Premium.
--
-- The two screens disagreed. Onboarding let anybody search and pick any town in
-- the US or Canada; Settings gated that search on `isSubscribed`. So a free
-- account could set a place it was not in exactly once, at signup, and then never
-- correct it -- which is the worst of both rules, because the one time you most
-- need to change it is right after you find out it is wrong.
--
-- That is not hypothetical. One live profile is labelled Toronto and positioned in
-- Vancouver, and its owner cannot fix it: the only control a free account has is
-- "Use my location", and that phone reports Vancouver every time.
--
-- The rule now: setting a town is free, at signup and afterwards. What Premium
-- buys is doing it again and again. A free account gets one change after
-- onboarding -- enough to correct a mistake, not enough to keep moving.
--
-- Creating the profile does not spend it. The trigger is `before update`, so the
-- town picked during onboarding is the starting position rather than the first
-- change, and somebody who signs up and immediately notices an error still has
-- their one.
--
-- A change made while subscribed does not spend it either. A lapsed subscriber
-- would otherwise come back to an allowance they had spent without ever being
-- told it was being counted.

-- The allowance, in one place, so it can be tuned without touching the trigger.
create or replace function private.arch_free_place_changes()
returns smallint
language sql
immutable
as $$ select 1::smallint $$;

-- Its own table, and not a column on `profiles` or `accounts`.
--
-- `profiles` is readable by anybody paired with you, so a counter there would
-- publish how often somebody has moved -- a number with no business on a profile,
-- and exactly the kind that ends up on a screen eventually. `accounts` is
-- self-readable but also self-*writable*, so a counter there could be set back to
-- zero by the client whose limit it is.
--
-- Here there is a read policy and no write policy at all. Nothing but the trigger
-- below writes it, and that runs `security definer`.
create table if not exists place_changes (
    account_id uuid primary key references accounts(id) on delete cascade,
    used smallint not null default 0,
    last_changed_at timestamptz
);

alter table place_changes enable row level security;

drop policy if exists place_changes_self_read on place_changes;
create policy place_changes_self_read on place_changes for select
    using (account_id = (select auth.uid()));

grant select on place_changes to authenticated;

create or replace function private.arch_count_place_change()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
    spent smallint;
    subscribed boolean;
begin
    -- Only a real move. `saveDetails` writes `place_id` on every edit, so
    -- correcting a job title would otherwise spend the one change somebody was
    -- saving for their address.
    if new.place_id is not distinct from old.place_id then
        return new;
    end if;

    subscribed := exists (
        select 1 from subscriptions s
         where s.account_id = new.account_id and s.expires_at > now()
    );
    if subscribed then
        return new;
    end if;

    select coalesce(pc.used, 0) into spent
      from place_changes pc where pc.account_id = new.account_id;
    spent := coalesce(spent, 0);

    if spent >= private.arch_free_place_changes() then
        raise exception 'no location changes left' using errcode = '42501';
    end if;

    insert into place_changes (account_id, used, last_changed_at)
    values (new.account_id, 1, now())
    on conflict (account_id) do update
        set used = place_changes.used + 1, last_changed_at = now();

    return new;
end;
$function$;

drop trigger if exists profiles_count_place_change on profiles;
create trigger profiles_count_place_change
    before update on profiles
    for each row execute function private.arch_count_place_change();
