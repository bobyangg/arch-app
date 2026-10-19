-- Reports reach a person.
--
-- **Until this, a report went nowhere.** The Report sheet said "Report sent" and
-- the app threw the report away -- nothing called the insert -- so `reports` was
-- empty the week external testing opened. The app now files it, with the
-- conversation it came from, the moment "Send report" is tapped. This is the
-- other half: somebody is told.
--
-- **Told from a sweep, the way push and the photo sweep are.** A cron job checks
-- whether any report is waiting and only then calls `report-alert`, which emails
-- the team (support@archdating.com, through Resend) and sends a notification to
-- every phone of every account in `private.moderators`. The report row is
-- committed before anything is sent, so a failed send is retried rather than
-- lost; a call made from a trigger would roll back the report or vanish.
--
-- **The conversation is attached to the report, not to the email.** The sheet
-- promises it is attached, and `conversation_id` is how. The email says how to
-- read it -- `private.report_conversation` in the SQL Editor -- rather than
-- carrying somebody's private messages into an inbox.
--
-- **The insert policy now says what a report may arrive with.** Before, a client
-- could file a report already marked `dismissed`, or reviewed. Now it arrives
-- new and unreviewed, never about yourself, and attached only to a conversation
-- both people are actually in.
--
-- Moderators are added by hand, in the SQL Editor:
--
--   insert into private.moderators (account_id) values ('<account id>');
--
-- Health:
--
--   select id, reason, created_at, emailed_at, pushed_at, alert_attempts, alert_error
--     from reports order by created_at desc limit 10;
--   select status_code, content from net._http_response order by id desc limit 5;

alter table reports
    add column conversation_id  uuid references conversations(id) on delete set null,
    add column emailed_at       timestamptz,
    add column pushed_at        timestamptz,
    add column alert_attempts   integer not null default 0,
    add column alert_error      text;

alter table reports
    add constraint reports_not_self check (reporter_id <> reported_id);

-- What the sweep asks about every two minutes. Almost always empty.
create index reports_waiting_idx on reports (created_at) where emailed_at is null;

drop policy reports_create on reports;
create policy reports_create on reports
    for insert with check (
        reporter_id = (select auth.uid())
        and state = 'new'
        and reviewed_at is null and reviewer_note is null
        and emailed_at is null and pushed_at is null
        and alert_attempts = 0 and alert_error is null
        and (conversation_id is null or exists (
            select 1 from conversations c
            where c.id = conversation_id
              and reporter_id in (c.lo_account, c.hi_account)
              and reported_id in (c.lo_account, c.hi_account)
        ))
    );


-- Who is told. Not readable through the API by anybody.
create table private.moderators (
    account_id      uuid primary key references public.accounts(id) on delete cascade,
    added_at        timestamptz not null default now()
);

revoke all on private.moderators from public, anon, authenticated;


-- What `report-alert` needs, in one call. In `public` because the function
-- reaches the database through the API, which does not serve `private`; callable
-- by the service role only.
create or replace function public.report_alerts_due(_limit integer default 20)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
    select jsonb_build_object(
        'reports', coalesce((
            select jsonb_agg(jsonb_build_object(
                'id', r.id,
                'reason', r.reason,
                'note', r.note,
                'created_at', r.created_at,
                'emailed', r.emailed_at is not null,
                'pushed', r.pushed_at is not null,
                'attempts', r.alert_attempts,
                'conversation_id', r.conversation_id,
                'messages', (select count(*) from messages m where m.conversation_id = r.conversation_id),
                'also_blocked', exists (select 1 from blocks b
                                        where b.blocker_id = r.reporter_id and b.blocked_id = r.reported_id),
                'reporter', jsonb_build_object(
                    'id', r.reporter_id,
                    'name', (select p.name from profiles p where p.account_id = r.reporter_id)),
                'reported', jsonb_build_object(
                    'id', r.reported_id,
                    'name', (select p.name from profiles p where p.account_id = r.reported_id),
                    'status', (select a.status from accounts a where a.id = r.reported_id),
                    'reports_about_them', (select count(*) from reports o where o.reported_id = r.reported_id))
            ) order by r.created_at)
            from (
                select * from reports
                where emailed_at is null
                  and alert_attempts < 30
                  and created_at > now() - interval '7 days'
                order by created_at
                limit _limit
            ) r
        ), '[]'::jsonb),
        'devices', coalesce((
            select jsonb_agg(jsonb_build_object('id', t.id, 'token', t.token, 'environment', t.environment))
            from push_tokens t
            join private.moderators mo on mo.account_id = t.account_id
        ), '[]'::jsonb)
    );
$function$;

revoke all on function public.report_alerts_due(integer) from public, anon, authenticated;
grant execute on function public.report_alerts_due(integer) to service_role;


-- Reading a reported conversation, for whoever handles the report. SQL Editor
-- only: `private` is not served, and nobody but the owner can execute it.
create or replace function private.report_conversation(_report uuid)
returns table(sent_at timestamptz, sender text, body text)
language sql
stable
security definer
set search_path to 'public'
as $function$
    select m.created_at,
           coalesce((select p.name from profiles p where p.account_id = m.sender_id), 'deleted account')
             || case when m.sender_id = r.reported_id then ' (reported)' else ' (reporter)' end,
           coalesce(m.body, '') || case when m.plan is not null then ' [a Date planner plan]' else '' end
    from reports r
    join messages m on m.conversation_id = r.conversation_id
    where r.id = _report
    order by m.created_at;
$function$;

revoke all on function private.report_conversation(uuid) from public, anon, authenticated;


-- The same shape as `sweep_push` and `sweep_photos`: ask first, and make no
-- request when nothing is waiting. The push job's secret, for the reason 021
-- gives: the database asking its own function to do a chore.
create or replace function private.sweep_reports()
returns void
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
    url text;
    secret text;
begin
    if not exists (
        select 1 from reports
        where emailed_at is null and alert_attempts < 30
          and created_at > now() - interval '7 days'
    ) then
        return;
    end if;

    select value into url from private_settings where key = 'report_alert_url';
    select value into secret from private_settings where key = 'push_secret';
    if url is null or secret is null then return; end if;

    perform net.http_post(
        url := url,
        body := '{}'::jsonb,
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-arch-cron', secret),
        timeout_milliseconds := 30000
    );
end;
$function$;

insert into private_settings (key, value)
values ('report_alert_url', 'https://bxuzpbzidrmoeietjnem.supabase.co/functions/v1/report-alert')
on conflict (key) do update set value = excluded.value;

-- Every two minutes. A report about somebody underage should not wait an hour,
-- and asking an almost-always-empty index costs nothing.
select cron.schedule('arch-report-sweep', '*/2 * * * *', 'select private.sweep_reports()');
