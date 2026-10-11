-- The data export lists the places you hid (032).
--
-- 031's `export_payload`, with one entry added beside the Date planner's
-- answers. Start any later change from here.
--
-- Its own file because the SQL lint cannot follow it: it calls
-- `arch_fresh_since`, defined in 028, which the lint does not read -- the same
-- reason 031 is not linted.

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
                'budget', dp.budget, 'distance', dp.distance, 'answered_at', dp.answered_at)
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
