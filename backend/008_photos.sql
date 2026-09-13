-- Arch: photo upload.
--
-- The `photos` bucket existed with **no policies at all**, which means no client
-- could write to it. That is the safe direction to be wrong in, but it is still
-- wrong, and it needed fixing deliberately rather than by widening something.
--
-- **Row first, bytes second.** The client mints the id and the path, inserts the
-- `photos` row, then uploads. That makes the storage rule a lookup against
-- `photos` rather than a convention about path shape, so the storage rule and the
-- table rule are literally the same rule and cannot drift apart.

-- What separates "a photo that exists" from "a photo somebody started uploading
-- and lost". Today that distinction lives only in `ProfileStore.uploads`, in
-- memory, and is gone when the app restarts.
alter table photos add column if not exists uploaded_at timestamptz;

-- Reordering writes several positions in one statement and every intermediate
-- state collides with the unique constraint. Deferring it to commit is the fix.
-- The alternatives are worse: renumbering through a gap needs the
-- `position between 0 and 5` CHECK relaxed, and delete-and-reinsert would lose
-- `id`, `state` and `created_at` -- and would launder a rejected photo back to
-- pending.
alter table photos drop constraint if exists photos_account_id_position_key;
alter table photos add constraint photos_account_id_position_key
    unique (account_id, position) deferrable initially immediate;

-- Six photos at 5MB is a generous ceiling for a 1080-square JPEG. Without a limit
-- the bucket accepts anything, of any size, of any type.
update storage.buckets
   set file_size_limit = 5242880,
       allowed_mime_types = array['image/jpeg']
 where id = 'photos';


-- ------------------------------------------------------------------ reordering
--
-- Takes the **whole** order, not a move. A delta is where the collision comes
-- from; a whole order is idempotent and can be re-sent after a dropped connection
-- without having to work out what landed.
create or replace function reorder_photos(ids uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare
    me uuid := auth.uid();
    mine integer;
begin
    if me is null then
        raise exception 'not signed in' using errcode = '28000';
    end if;

    select count(*) into mine from photos where account_id = me;

    -- Every id must be the caller's, and the array must be their whole set. A
    -- partial array leaves gaps in the positions; a duplicated id renumbers one
    -- photo twice and silently drops another.
    if array_length(ids, 1) is distinct from mine
       or exists (select 1 from unnest(ids) as u(id)
                   where not exists (select 1 from photos p
                                      where p.id = u.id and p.account_id = me))
       or (select count(distinct u.id) from unnest(ids) as u(id)) <> mine then
        raise exception 'that is not your photo order' using errcode = '42501';
    end if;

    set constraints photos_account_id_position_key deferred;

    update photos p
       set position = u.ord - 1
      from unnest(ids) with ordinality as u(id, ord)
     where p.id = u.id and p.account_id = me;
end;
$$;

revoke all on function reorder_photos(uuid[]) from public, anon;
grant execute on function reorder_photos(uuid[]) to authenticated;


-- ------------------------------------------------------- the storage policies
--
-- All of them key on a `photos` row rather than on the shape of the object path.
--
-- Deliberately plain `for select` rather than `storage.allow_any_operation(...)`.
-- That helper exists to stop a read policy also permitting `object.list`, but the
-- USING clause is evaluated per row either way, so a listing returns exactly the
-- set a fetch already allows and reveals nothing more. The operation names it
-- needs are set per request by the Storage service and cannot be enumerated from
-- SQL; guessing one wrong fails closed, and a photo that silently never loads
-- reads as a network fault rather than as a policy.

create policy photos_object_insert on storage.objects
    for insert to authenticated
    with check (
        bucket_id = 'photos'
        and exists (
            select 1 from public.photos p
            where p.storage_path = storage.objects.name
              and p.account_id = (select auth.uid())));

create policy photos_object_read on storage.objects
    for select to authenticated
    using (
        bucket_id = 'photos'
        and exists (
            select 1 from public.photos p
            where p.storage_path = storage.objects.name
              and (p.account_id = (select auth.uid())
                   -- Only an approved photo, and only to somebody who can already
                   -- see the profile it belongs to. A block closes this the moment
                   -- it is written, which is why the bucket is private and reads
                   -- go through short-lived signed URLs.
                   or (p.state = 'approved'
                       and private.arch_can_see(p.account_id)))));

create policy photos_object_delete on storage.objects
    for delete to authenticated
    using (
        bucket_id = 'photos'
        and exists (
            select 1 from public.photos p
            where p.storage_path = storage.objects.name
              and p.account_id = (select auth.uid())));

-- **No UPDATE policy, and that omission is load-bearing.** With one, somebody
-- could get a mild photo approved and then overwrite the bytes at the same path
-- with a different image. No update means no upsert, which is what makes
-- moderation mean anything. Replacing a photo is a delete and a new row.
--
-- Postgres answers a write with no permissive policy by matching zero rows rather
-- than by raising, so a test for this has to count rows and not catch an
-- exception -- see 009_photos_test.sql, where the first version did the latter
-- and reported a pass that meant nothing.
