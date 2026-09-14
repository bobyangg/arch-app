-- Arch: asking a person to look at a refused photograph again.
--
-- **This table was already in the database and in no file.** `011_photo_moderation`
-- describes it in a comment -- "mirrors `appeals` in shape and in its unique
-- constraint" -- and never creates it, so a rebuild from this directory came up a
-- table short while the live project worked perfectly. Written by reading the
-- database back rather than from memory of what it should contain.
--
-- Idempotent throughout, because the live project already has all of this: running
-- it there changes nothing, and running it on an empty database produces what the
-- live one has.
--
-- One ask per photograph, enforced by the unique constraint rather than by the app
-- asking nicely. A second look is not a second chance, and the screen says so.

create table if not exists photo_reviews (
    id          uuid primary key default uuid_generate_v4(),
    photo_id    uuid not null references photos(id) on delete cascade,
    -- Nullable so the row can exist before anybody types anything, capped so a
    -- 40,000-word essay cannot be pasted into a moderation queue.
    body        text check (body is null or length(body) <= 500),
    -- Shared with `appeals`: submitted -> upheld | overturned.
    state       appeal_state not null default 'submitted',
    created_at  timestamptz not null default now(),
    reviewed_at timestamptz,
    -- The whole point. Deleting the photograph takes the ask with it (cascade
    -- above), so re-uploading and asking again is possible; asking twice about the
    -- same photograph is not.
    unique (photo_id)
);

alter table photo_reviews enable row level security;

-- Your own, and only through your own photographs. There is no update policy and
-- no delete policy on purpose: withdrawing an ask would let somebody ask, withdraw
-- and ask again, which is the unique constraint defeated in three steps.
drop policy if exists photo_reviews_self_read on photo_reviews;
create policy photo_reviews_self_read on photo_reviews
    for select using (
        exists (
            select 1 from photos p
            where p.id = photo_reviews.photo_id
              and p.account_id = (select auth.uid())
        )
    );

drop policy if exists photo_reviews_self_create on photo_reviews;
create policy photo_reviews_self_create on photo_reviews
    for insert with check (
        exists (
            select 1 from photos p
            where p.id = photo_reviews.photo_id
              and p.account_id = (select auth.uid())
        )
    );

-- `auth.uid()` is wrapped in a sub-select in both, which is not a stylistic choice:
-- unwrapped it is re-evaluated per row, and the advisor flags it. The rest of the
-- schema does the same.
