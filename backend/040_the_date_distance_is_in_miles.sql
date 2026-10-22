-- How far somebody would travel for a date, in miles.
--
-- The Date planner's fifth question was "Keep it walkable" or "A short ride is
-- fine". It becomes a slider, 1 to 15 miles: each person's plan stays within
-- their own distance of them, and a mile or less keeps every stop on foot, as
-- "walkable" did.
--
-- **`distance` stays.** Builds from before the slider read and write it and
-- know nothing of `reach_miles`, which they ignore. Newer builds write both --
-- a mile or less is 'walkable', anything more 'ride' -- and read `reach_miles`
-- when it is there. Null means "read `distance` instead": walkable is a mile, a
-- ride six. Everybody who has answered keeps a sensible distance without
-- answering again.
--
-- **The trigger keeps the two in step.** The app saves with an upsert that
-- only updates the columns it sends, so somebody re-answering on an older build
-- would change `distance` and leave a `reach_miles` from a newer one behind:
-- "walkable" beside ten miles. When `distance` changes and the miles do not,
-- the miles go and `distance` speaks for them.
--
-- Who can read it is 029's policy, unchanged: you, and the people you are in a
-- conversation with. Account deletion already removes the row (030).
--
-- Not yet here: "Download your data". `export_payload` (last redefined in 033)
-- lists the Date planner's columns by name, so it needs `reach_miles` added;
-- that comes with the build that uses it.
--
-- Applied in the SQL Editor on 2026-10-22, ahead of any build that writes it.
-- Safe to run again: a second run finds everything already there and changes
-- nothing (the first version of this file stopped with "column reach_miles
-- already exists").

begin;

alter table date_preferences
    add column if not exists reach_miles smallint check (reach_miles between 1 and 15);

comment on column date_preferences.reach_miles is
    'How far they would travel for a date, in miles. Null: read distance instead (walkable = 1, ride = 6).';

-- An older build re-answering sends distance but not reach_miles. When the
-- two would disagree, the miles go and distance speaks for them.
create or replace function private.date_preferences_keep_in_step()
returns trigger language plpgsql as $$
begin
    if new.distance is distinct from old.distance
       and new.reach_miles is not distinct from old.reach_miles then
        new.reach_miles := null;
    end if;
    return new;
end;
$$;

create or replace trigger date_preferences_keep_in_step
    before update on date_preferences
    for each row execute function private.date_preferences_keep_in_step();

commit;
