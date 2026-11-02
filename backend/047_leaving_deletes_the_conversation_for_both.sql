-- Leaving a conversation deletes it, for both people.
--
-- Until now an ended conversation stayed in the database for good. Neither
-- person could see it -- Messages shows open conversations only -- but the app
-- still downloaded it, and that is what closed Bob's app at launch: an ended
-- thread with alwin from Oct 21 and a new one after they were introduced
-- again, two threads with one person.
--
-- Now leaving, declining, blocking and deleting your account all end the same
-- way they always did (`state = 'ended'`, so the other side still cannot tell
-- them apart), and the conversation and its messages are then deleted.
--
-- **Not at once, but within the hour.** Two things have to happen first:
--
--   - A report filed in the same moment as a block names the conversation,
--     and would fail if it had already gone. So nothing is deleted until ten
--     minutes after it ended.
--   - The introductions record (`analytics.record`, privacy policy) notes
--     what followed each introduction: whether a conversation started, who
--     wrote first, whether there was a reply, how many messages in the first
--     week. The sweep runs in the same job, straight after it, so every
--     conversation is counted before it goes.
--
-- **A reported conversation is kept**, out of both people's sight as before,
-- because the moderator reading the report needs it. That covers a report
-- naming the conversation and one between the same two people from a profile.
--
-- **The record no longer forgets.** It recomputes the last 14 nights every
-- hour, and found a deleted conversation as "no conversation" -- it would
-- have overwritten what it had recorded. Now a recorded outcome only grows.
--
-- **Conversations that ended before this are left alone.** `ended_at` starts
-- empty for them, and the sweep only takes conversations with an end time.
-- Deleting those is a separate, explicit decision.
--
-- In one transaction, with a check at the end.

begin;

-- When it ended. Written by the trigger below and nothing else.
alter table public.conversations add column if not exists ended_at timestamptz;

-- Stamped when the state becomes ended, whoever ends it: the app (leaving,
-- declining), `block_ends_conversations`, `delete_account`. Every other
-- update keeps the old value, so a client cannot move the time and hurry its
-- own conversation out of a moderator's reach. Named to run after
-- `conversations_guard`; before-triggers run in name order.
create or replace function private.stamp_conversation_end()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
    if new.state = 'ended' then
        new.ended_at := case when old.state = 'ended' then old.ended_at else now() end;
    else
        new.ended_at := null;
    end if;
    return new;
end;
$function$;

drop trigger if exists conversations_stamp_end on public.conversations;
create trigger conversations_stamp_end
    before update on public.conversations
    for each row execute function private.stamp_conversation_end();

-- The deletion. Messages and queued pushes go with it (`on delete cascade`).
create or replace function private.sweep_ended_conversations()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
    gone integer;
begin
    delete from public.conversations c
     where c.state = 'ended'
       and c.ended_at < now() - interval '10 minutes'
       and not exists (
           select 1 from public.reports r
            where r.conversation_id = c.id
               or (r.reporter_id = c.lo_account and r.reported_id = c.hi_account)
               or (r.reporter_id = c.hi_account and r.reported_id = c.lo_account));
    get diagnostics gone = row_count;
    return gone;
end;
$function$;

revoke all on function private.stamp_conversation_end() from public, anon, authenticated;
revoke all on function private.sweep_ended_conversations() from public, anon, authenticated;

-- The record, as before, except that a deleted conversation no longer erases
-- what was recorded about it. The changes are marked.
create or replace function analytics.record()
returns void
language plpgsql
security definer
set search_path to 'public', 'analytics'
as $function$
declare
    today date := private.arch_night();
begin
    insert into analytics.subjects (account_id)
    select distinct side.id
      from pairings p
     cross join lateral (values (p.lo_account), (p.hi_account)) as side(id)
     where p.night >= today - 14
    on conflict (account_id) do nothing;

    insert into analytics.introductions as i (
        night, subject_a, subject_b, score, rank_a, rank_b,
        age_a, age_b, gender_a, gender_b,
        answers_a, answers_b, requirements_a, requirements_b, distance_km)
    select p.night, sa.subject, sb.subject, p.score,
           (select e.rank from match_edges e
             where e.night = p.night and e.account_id = p.lo_account and e.other_id = p.hi_account),
           (select e.rank from match_edges e
             where e.night = p.night and e.account_id = p.hi_account and e.other_id = p.lo_account),
           ma.age, mb.age, ma.gender::text, mb.gender::text,
           ma.ans, mb.ans, ma.req, mb.req,
           round(analytics.km(ma.lat, ma.lon, mb.lat, mb.lon))::smallint
      from pairings p
      join analytics.subjects sa on sa.account_id = p.lo_account
      join analytics.subjects sb on sb.account_id = p.hi_account
      left join match_people ma on ma.night = p.night and ma.account_id = p.lo_account
      left join match_people mb on mb.night = p.night and mb.account_id = p.hi_account
     where p.night >= today - 14
    on conflict (night, subject_a, subject_b) do update
       set age_a          = coalesce(i.age_a,          excluded.age_a),
           age_b          = coalesce(i.age_b,          excluded.age_b),
           gender_a       = coalesce(i.gender_a,       excluded.gender_a),
           gender_b       = coalesce(i.gender_b,       excluded.gender_b),
           answers_a      = coalesce(i.answers_a,      excluded.answers_a),
           answers_b      = coalesce(i.answers_b,      excluded.answers_b),
           requirements_a = coalesce(i.requirements_a, excluded.requirements_a),
           requirements_b = coalesce(i.requirements_b, excluded.requirements_b),
           distance_km    = coalesce(i.distance_km,    excluded.distance_km);

    with live as (
        select p.night, p.lo_account as a, p.hi_account as b, p.created_at as introduced,
               sa.subject as subject_a, sb.subject as subject_b
          from pairings p
          join analytics.subjects sa on sa.account_id = p.lo_account
          join analytics.subjects sb on sb.account_id = p.hi_account
         where p.night >= today - 14
    ),
    outcome as (
        select l.night, l.subject_a, l.subject_b,
               c.id as conversation_id, c.created_at as started, c.opened_by,
               case when c.opened_by = l.a then l.subject_a
                    when c.opened_by = l.b then l.subject_b end as opener,
               exists (
                   select 1 from dismissals d
                    where d.night = l.night
                      and d.account_id in (l.a, l.b)
                      and d.other_account_id in (l.a, l.b)
               ) as any_dismissal
          from live l
          left join conversations c
            on c.lo_account = l.a and c.hi_account = l.b
           and c.created_at >= l.introduced
           and c.created_at <  l.introduced + interval '3 days'
    )
    update analytics.introductions i
       -- **Changed.** Each of these keeps what was recorded when the
       -- conversation is no longer there to read.
       set conversation_at     = coalesce(o.started, i.conversation_at),
           opener              = coalesce(o.opener, i.opener),
           replied             = i.replied
                                 or coalesce((select bool_or(m.sender_id <> o.opened_by)
                                                from messages m where m.conversation_id = o.conversation_id), false),
           messages_first_week = greatest(i.messages_first_week,
                                          coalesce((select count(*)
                                                      from messages m where m.conversation_id = o.conversation_id
                                                       and m.created_at < o.started + interval '7 days'), 0)),
           dismissed           = o.any_dismissal and o.conversation_id is null
                                 and i.conversation_at is null,
           updated_at          = now()
      from outcome o
     where i.night = o.night and i.subject_a = o.subject_a and i.subject_b = o.subject_b;

    delete from match_edges  where night < today - 90;
    delete from match_state  where night < today - 90;
    delete from match_people where night < today - 90;
end;
$function$;

-- The existing hourly job, now record-then-sweep in one command, so it is one
-- transaction: if the record fails, nothing is deleted. Same name, so this
-- replaces the job rather than adding a second.
select cron.schedule('arch-matcher-analytics', '47 * * * *',
                     'select analytics.record(); select private.sweep_ended_conversations();');

-- ------------------------------------------------------------ the check
-- A conversation between two people who have no live one is made, ended,
-- swept, and then all of it rolled back with the inner block.
do $check$
declare
    a uuid;
    b uuid;
    t uuid;
    stamped timestamptz;
    others_before integer;
begin
    if (select count(*) from cron.job where jobname = 'arch-matcher-analytics'
          and command like '%sweep_ended_conversations%') <> 1 then
        raise exception '047: the hourly job does not sweep';
    end if;
    if exists (select 1 from public.conversations where state = 'ended' and ended_at is not null) then
        raise exception '047: an earlier ended conversation was given an end time';
    end if;

    select x.id, y.id into a, b
      from public.accounts x, public.accounts y
     where x.id < y.id and x.status = 'active' and y.status = 'active'
       and not exists (select 1 from public.conversations c
                        where c.lo_account = x.id and c.hi_account = y.id and c.state <> 'ended')
     limit 1;
    if a is null then
        return;
    end if;

    begin
        insert into public.conversations (lo_account, hi_account, state, opened_by, last_message_at)
        values (a, b, 'request', a, now()) returning id into t;

        update public.conversations set state = 'ended' where id = t;
        select ended_at into stamped from public.conversations where id = t;
        if stamped is null then
            raise exception '047: ending did not stamp ended_at';
        end if;

        update public.conversations set ended_at = now() - interval '1 day' where id = t;
        if (select ended_at from public.conversations where id = t) <> stamped then
            raise exception '047: ended_at could be moved';
        end if;

        -- Ten minutes have to pass; in a transaction they cannot, so the
        -- stamp is moved with the trigger off.
        alter table public.conversations disable trigger conversations_stamp_end;
        update public.conversations set ended_at = now() - interval '11 minutes' where id = t;
        alter table public.conversations enable trigger conversations_stamp_end;

        select count(*) into others_before from public.conversations where id <> t;
        perform analytics.record();
        perform private.sweep_ended_conversations();
        if exists (select 1 from public.conversations where id = t) then
            raise exception '047: the sweep did not delete an ended conversation';
        end if;
        if (select count(*) from public.conversations where id <> t) <> others_before then
            raise exception '047: the sweep deleted a conversation it should have kept';
        end if;

        raise exception 'rolled back on purpose';
    exception when others then
        if sqlerrm <> 'rolled back on purpose' then
            raise;
        end if;
    end;
end
$check$;

commit;
