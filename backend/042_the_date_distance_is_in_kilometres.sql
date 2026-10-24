-- The Date planner's distance is in kilometres.
--
-- The slider from 040 asked in miles, 1 to 15. It now asks in kilometres, 1 to
-- 25, in `reach_km`. Nothing is dropped:
--
--   * `reach_miles` stays, and newer builds still write it -- the nearest whole
--     mile -- for the builds that read only that; `distance` stays beside both.
--   * Answers already given in miles are copied across, converted.
--   * The trigger keeps the three in step for older builds: one that changes the
--     miles or walk-or-ride without kilometres clears `reach_km`, so the app
--     reads the newer answer from the miles instead of a stale number.
--
-- The data export includes `reach_km` (041's function, one field added).
--
-- Safe to run again.

begin;

alter table date_preferences
    add column if not exists reach_km smallint check (reach_km between 1 and 25);

comment on column date_preferences.reach_km is
    'How far they would travel for a date, in kilometres. Null: read reach_miles, then distance (walkable = 2 km, ride = 10 km).';

update date_preferences
   set reach_km = least(25, greatest(1, round(reach_miles * 1.609344)))::smallint
 where reach_miles is not null and reach_km is null;

-- Kilometres, miles and walk-or-ride, kept saying the same thing. A build that
-- writes kilometres writes all three; an older one writes only some, and the
-- ones it leaves are cleared so the app reads what it did write.
create or replace function private.date_preferences_keep_in_step()
returns trigger language plpgsql as $$
begin
    if new.reach_km is not distinct from old.reach_km
       and (new.reach_miles is distinct from old.reach_miles
            or new.distance is distinct from old.distance) then
        new.reach_km := null;
    end if;
    if new.distance is distinct from old.distance
       and new.reach_miles is not distinct from old.reach_miles
       and new.reach_km is null then
        new.reach_miles := null;
    end if;
    return new;
end;
$$;

create or replace trigger date_preferences_keep_in_step
    before update on date_preferences
    for each row execute function private.date_preferences_keep_in_step();

create or replace function private.export_payload(_account uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
    select jsonb_build_object(
        'exported_at', now(),
        'account', (
            select jsonb_build_object('created_at', a.created_at, 'email', a.apple_email)
            from accounts a where a.id = _account
        ),
        'profile', (
            select jsonb_build_object(
                'name', p.name, 'birthdate', p.birthdate, 'gender', p.gender,
                'pronouns', p.pronouns, 'place', p.place_id,
                'height_cm', p.height_cm, 'work', p.work,
                'prompts', (select coalesce(jsonb_agg(jsonb_build_object(
                        'question', pr.prompt_key, 'answer', pr.answer)
                        order by pr.position), '[]'::jsonb)
                    from profile_prompts pr where pr.account_id = _account),
                'interests', (select coalesce(jsonb_agg(i.text order by i.position), '[]'::jsonb)
                    from profile_interests i where i.account_id = _account)
            )
            from profiles p where p.account_id = _account
        ),
        -- Your own answers, which nobody else has ever been able to see.
        'questionnaire', (
            select coalesce(jsonb_object_agg(q.question_id, q.option_index), '{}'::jsonb)
            from questionnaire_answers q where q.account_id = _account
        ),
        -- What you told the Date planner a date should be like. Read by the
        -- apps of people you are messaging, never shown to them (029).
        'date_planner', (
            select jsonb_build_object(
                'style', dp.style, 'time_of_day', dp.time_of_day, 'drinks', dp.drinks,
                'budget', dp.budget, 'distance', dp.distance, 'reach_km', dp.reach_km, 'reach_miles', dp.reach_miles,
                'answered_at', dp.answered_at)
            from date_preferences dp where dp.account_id = _account
        ),
        -- Places you told the Date planner were not for you (032).
        'places_you_hid', (
            select coalesce(jsonb_agg(jsonb_build_object('name', h.name, 'at', h.hidden_at)
                order by h.hidden_at), '[]'::jsonb)
            from hidden_places h where h.account_id = _account
        ),
        'settings', (
            select jsonb_build_object(
                'seeking', d.seeking, 'distance_miles', d.distance_miles,
                'min_age', d.min_age, 'max_age', d.max_age,
                'paused', d.paused, 'notify_messages', d.notify_messages)
            from discovery_settings d where d.account_id = _account
        ),
        -- Since the account was last deleted, if it ever was: a fresh start
        -- exports nothing from before it.
        'conversations', (
            select coalesce(jsonb_agg(c.payload order by c.started), '[]'::jsonb)
            from (
                select conv.created_at as started,
                    jsonb_build_object(
                        'with', (select pr.name from profiles pr
                                  where pr.account_id = case when conv.lo_account = _account
                                        then conv.hi_account else conv.lo_account end),
                        'state', conv.state,
                        'messages', (select coalesce(jsonb_agg(jsonb_build_object(
                                'at', m.created_at,
                                'from', case when m.sender_id = _account then 'you' else 'them' end,
                                'body', m.body) order by m.created_at), '[]'::jsonb)
                            from messages m where m.conversation_id = conv.id)
                    ) as payload
                from conversations conv
                where _account in (conv.lo_account, conv.hi_account)
                  and conv.created_at >= private.arch_fresh_since(_account)
            ) c
        ),
        -- Who has been in your roster and when. Names and nights, no score.
        'roster_history', (
            select coalesce(jsonb_agg(jsonb_build_object(
                'night', pg.night,
                'name', (select pr.name from profiles pr where pr.account_id = pg.other))
                order by pg.night desc), '[]'::jsonb)
            from (
                select night, case when lo_account = _account then hi_account
                                   else lo_account end as other
                from pairings where _account in (lo_account, hi_account)
            ) pg
        ),
        -- Blocks **you** placed. Never ones placed on you.
        'people_you_blocked', (
            select coalesce(jsonb_agg(jsonb_build_object('at', b.created_at)), '[]'::jsonb)
            from blocks b where b.blocker_id = _account
        ),
        'photos', (
            select coalesce(jsonb_agg(jsonb_build_object(
                'file', 'photos/' || (ph.position + 1) || '.jpg',
                'state', ph.state, 'added', ph.created_at) order by ph.position), '[]'::jsonb)
            from photos ph where ph.account_id = _account
        )
    );
$function$;

commit;
