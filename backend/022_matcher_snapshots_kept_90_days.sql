-- The matcher's nightly snapshots: deleted with the account, and gone after 90 days.
--
-- `match_people`, `match_edges` and `match_state` hold what the matcher used each
-- night -- age, gender and approximate position per person, the candidate graph,
-- the proposal rounds. 021 left them kept indefinitely, pending a decision. The
-- decision: delete a person's rows when they delete their account, and everybody's
-- after ninety days. The privacy policy says exactly this, and this migration is
-- what makes it true.
--
-- Nothing the analytics dataset needs is lost: `analytics.record()` takes the two
-- numbers it wants from these tables within the hour, and the record it keeps is
-- pseudonymous and severed from the account on deletion (021).

-- On deletion. `delete_account` keeps the accounts row and stamps `deleted_at`, so
-- that stamp is the signal -- the same one `analytics.forget_subject` listens to.
-- Removes the person from every night: their own rows, the edges pointing at them,
-- and their id from other people's lists of who they were paired with.
create or replace function private.forget_match_history()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
    if new.deleted_at is not null and new.deleted_at is distinct from old.deleted_at then
        delete from match_people where account_id = new.id;
        delete from match_edges  where account_id = new.id or other_id = new.id;
        delete from match_state  where account_id = new.id;
        update match_state set taken = array_remove(taken, new.id) where new.id = any(taken);
    end if;
    return new;
end;
$function$;

drop trigger if exists accounts_forget_match_history on accounts;
create trigger accounts_forget_match_history
    after update of deleted_at on accounts
    for each row execute function private.forget_match_history();

-- After 90 days. The hourly analytics job is where the snapshots are last read,
-- so it is also where they are let go.
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

    -- Ninety days, as the privacy policy says.
    delete from match_edges  where night < today - 90;
    delete from match_state  where night < today - 90;
    delete from match_people where night < today - 90;
end;
$function$;
