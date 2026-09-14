-- Arch: notes on your own profile.
--
-- The second half of the profile review. The first half -- what people write
-- about -- is arithmetic the app already had. This half is a model reading the
-- photographs and the answers and saying what is vague and what to say instead.
-- It runs in the `review` edge function, and what it said is kept here.
--
-- **Kept, so that a review is read more than it is run.** Opening the screen
-- twice must not cost two calls, and a note should still be there tomorrow without
-- the model on the line. `profile_hash` is a digest of exactly what was reviewed:
-- same profile, same notes, and the function hands back the row. Change a photo
-- or an answer and the hash changes with it.
--
-- **Written only by the server.** There is no insert policy. The row is the
-- reviewer's answer, and a client that could write its own would be a client that
-- could put words in the reviewer's mouth -- and then show them to itself as if
-- they were somebody else's opinion. Read by the owner and nobody else: the notes
-- are about your profile and are nobody else's business, including the people who
-- will see the profile they are about.
--
-- Applied as migration `profile_review`.

create table profile_reviews (
    id              uuid primary key default uuid_generate_v4(),
    account_id      uuid not null references accounts(id) on delete cascade,
    -- sha-256 of the reviewed profile, hex. What "the same profile" means.
    profile_hash    text not null,
    -- The reviewer's answer, in the shape `ProfileNotes` decodes on the phone.
    notes           jsonb not null,
    -- Which model wrote it. A note is read long after it is written, and a
    -- reader wondering why two reviews disagree should be able to find out.
    model           text not null,
    created_at      timestamptz not null default now()
);

-- The function's two reads: "is there one for this exact profile" and "how many
-- today". Both walk this.
create index profile_reviews_account_idx
    on profile_reviews (account_id, created_at desc);

alter table profile_reviews enable row level security;
create policy profile_reviews_self_read on profile_reviews
    for select using (account_id = (select auth.uid()));
-- No insert, update or delete policy. The `review` function writes with the
-- service key, after it has checked the subscription.
