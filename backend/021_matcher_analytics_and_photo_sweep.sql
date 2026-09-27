-- Two things about keeping data: what to keep for studying the matcher, and what
-- to stop keeping by accident.
--
-- 1. MATCHER ANALYTICS, APART FROM LIVE DATA
--
-- The question worth being able to answer is whether the matcher works: does a
-- higher score, or being somebody's first choice rather than their fifth, make a
-- conversation more likely? Answering it needs a record of every introduction and
-- what came of it, kept after the live tables have moved on.
--
-- It lives in its own schema, `analytics`, which Supabase's API does not serve --
-- only `public` is exposed -- and whose tables have row security and no policies.
-- The app cannot read it or write it. You read it from the SQL editor.
--
-- **Pseudonymous, and severed on deletion.** `analytics.introductions` never
-- holds an account id. It holds a random `subject` per person, and
-- `analytics.subjects` is the only thing that maps one to the other. So one
-- person can still be followed across nights -- which most matcher questions
-- need -- and deleting an account deletes its row in `subjects`, after which
-- that person's history is still in the dataset and no longer leads back to them.
--
-- Recorded per introduction: the matcher's own numbers (score, and where each
-- person ranked the other), and what happened (a conversation, who wrote first,
-- whether they got a reply, how much was said in the first week, whether it was
-- dismissed). Not *who* dismissed: Arch promises nobody is ever told, and a
-- dataset is a thing people look at.
--
-- Outcomes keep updating for fourteen days after an introduction, because a
-- conversation takes time to happen and a reply takes time to arrive. It runs as
-- its own hourly job rather than inside `run_nightly_match`, so that nothing in
-- here can ever stop a roster being built.
--
-- 2. THE MATCHER'S WORKING DATA IS KEPT, FOR NOW
--
-- `match_people`, `match_edges` and `match_state` are the matcher's scratch
-- space: one night's population, its candidate graph, its proposal rounds. Only
-- tonight's is ever read by the matcher, and every night's is kept -- each row an
-- age, a gender and a pair of coordinates. A version of this migration pruned
-- them after seven days; it was taken out before it ever ran, because they are
-- matcher data too (the score of every candidate pair, not only the matched
-- ones) and deleting them was not what was agreed. Whether to keep them, and in
-- what form, is still an open decision -- see `analytics.record()`.
--
-- 3. PHOTO FILES THAT OUTLIVE THEIR PHOTOS
--
-- Deleting a photograph, or an account, removes the `photos` row and never the
-- file: Supabase refuses deletes on `storage.objects` from SQL
-- (`protect_objects_delete`), so `delete_account` could not have removed them if
-- it had tried. 56 of the 72 files in the bucket had no row. A sweep now asks an
-- edge function, which uses the Storage API, to remove any file with no row that
-- is more than an hour old -- the hour so an upload in flight, whose row is
-- written first and whose bytes follow, is never mistaken for an orphan.

-- ------------------------------------------------------------------ analytics

create schema if not exists analytics;
revoke all on schema analytics from public, anon, authenticated;

create table if not exists analytics.subjects (
    -- Cascades if an account row is ever removed outright. Accounts are normally
    -- kept on deletion (see 016), which is why the trigger below exists.
    account_id uuid primary key references accounts(id) on delete cascade,
    subject    uuid not null unique default gen_random_uuid()
);

create table if not exists analytics.introductions (
    night               date not null,
    -- The pair, as pseudonyms. `a` was the pairing's `lo_account`, `b` its
    -- `hi_account`; that order is arbitrary and means nothing.
    subject_a           uuid not null,
    subject_b           uuid not null,
    -- The matcher's pair score (0 to 13), and where each ranked the other among
    -- that night's candidates, 1 being best. Rank is null if the night's edges
    -- were already pruned when the introduction was first recorded.
    score               numeric,
    rank_a              integer,
    rank_b              integer,
    -- What came of it.
    conversation_at     timestamptz,
    opener              uuid,
    replied             boolean not null default false,
    messages_first_week integer not null default 0,
    dismissed           boolean not null default false,
    updated_at          timestamptz not null default now(),
    primary key (night, subject_a, subject_b)
);

alter table analytics.subjects enable row level security;
alter table analytics.introductions enable row level security;
revoke all on all tables in schema analytics from public, anon, authenticated;

-- Deleting an account severs its history from it. `delete_account` keeps the
-- accounts row and stamps `deleted_at`, so that stamp is the signal.
create or replace function analytics.forget_subject()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'analytics'
as $function$
begin
    if new.deleted_at is not null and new.deleted_at is distinct from old.deleted_at then
        delete from analytics.subjects where account_id = new.id;
    end if;
    return new;
end;
$function$;

drop trigger if exists accounts_forget_subject on accounts;
create trigger accounts_forget_subject
    after update of deleted_at on accounts
    for each row execute function analytics.forget_subject();

create or replace function analytics.record()
returns void
language plpgsql
security definer
set search_path to 'public', 'analytics'
as $function$
declare
    today date := private.arch_night();
begin
    -- A pseudonym for everybody in a recent introduction.
    insert into analytics.subjects (account_id)
    select distinct side.id
      from pairings p
     cross join lateral (values (p.lo_account), (p.hi_account)) as side(id)
     where p.night >= today - 14
    on conflict (account_id) do nothing;

    -- New introductions, with the matcher's numbers while its edges still exist.
    insert into analytics.introductions (night, subject_a, subject_b, score, rank_a, rank_b)
    select p.night, sa.subject, sb.subject, p.score,
           (select e.rank from match_edges e
             where e.night = p.night and e.account_id = p.lo_account and e.other_id = p.hi_account),
           (select e.rank from match_edges e
             where e.night = p.night and e.account_id = p.hi_account and e.other_id = p.lo_account)
      from pairings p
      join analytics.subjects sa on sa.account_id = p.lo_account
      join analytics.subjects sb on sb.account_id = p.hi_account
     where p.night >= today - 14
    on conflict (night, subject_a, subject_b) do nothing;

    -- What came of each, for as long as it can still change.
    --
    -- A conversation counts for an introduction if it began after the pair was
    -- introduced and within three days of it -- the two nights they could write
    -- plus slack. Conversations are one per pair for good, so one begun in an
    -- earlier introduction is not credited to a later one.
    --
    -- `dismissed` is only true where no conversation began: `start_conversation`
    -- writes dismissal rows for both sides as it opens one, and those are the
    -- mechanism of writing to somebody, not a dismissal.
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
       set conversation_at     = o.started,
           opener              = o.opener,
           replied             = coalesce((select bool_or(m.sender_id <> o.opened_by)
                                             from messages m where m.conversation_id = o.conversation_id), false),
           messages_first_week = coalesce((select count(*)
                                             from messages m where m.conversation_id = o.conversation_id
                                              and m.created_at < o.started + interval '7 days'), 0),
           dismissed           = o.any_dismissal and o.conversation_id is null,
           updated_at          = now()
      from outcome o
     where i.night = o.night and i.subject_a = o.subject_a and i.subject_b = o.subject_b;

    -- The matcher's scratch space, now that the two numbers wanted from it are
    -- recorded above. Only tonight's is ever read.
    -- No pruning here. The matcher's scratch tables are left as they are until
    -- somebody decides what should happen to them -- see the header.
end;
$function$;

-- ------------------------------------------------------------------- photos

-- Files in the photo bucket that no photograph owns. Readable only by the
-- service role: listing storage paths is nobody else's business.
create or replace function public.orphaned_photo_paths(max_rows integer default 500)
returns table(path text)
language sql
stable
security definer
set search_path to 'public', 'storage'
as $$
    select o.name
      from storage.objects o
     where o.bucket_id = 'photos'
       and o.created_at < now() - interval '1 hour'
       and not exists (select 1 from public.photos p where p.storage_path = o.name)
     order by o.created_at
     limit greatest(1, least(max_rows, 1000))
$$;

revoke all on function public.orphaned_photo_paths(integer) from public, anon, authenticated;
grant execute on function public.orphaned_photo_paths(integer) to service_role;

-- The same shape as `sweep_push`: count first, and make no request at all when
-- there is nothing to do. The secret is the push job's, deliberately -- both are
-- the database asking one of its own functions to do a chore, and one shared
-- secret is one fewer thing to set by hand in the dashboard.
create or replace function private.sweep_photos()
returns void
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
    url text;
    secret text;
begin
    if not exists (select 1 from public.orphaned_photo_paths(1)) then
        return;
    end if;
    select value into url from private_settings where key = 'photo_sweep_url';
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
values ('photo_sweep_url', 'https://bxuzpbzidrmoeietjnem.supabase.co/functions/v1/photo-sweep')
on conflict (key) do update set value = excluded.value;

-- Hourly, at minutes the matcher (:07) and the push sweep (every minute) are not
-- competing for.
select cron.schedule('arch-photo-sweep', '37 * * * *', 'select private.sweep_photos()');
select cron.schedule('arch-matcher-analytics', '47 * * * *', 'select analytics.record()');
