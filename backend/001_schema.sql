-- Arch: the tables.
--
-- Written for Supabase, so `auth.users` already exists and `auth.uid()` is the
-- signed-in account. Everything here hangs off that.
--
-- Four of Arch's promises are structural rather than cosmetic, and this file is
-- where they are kept or lost:
--
--   1. Questionnaire answers are never shown to anybody. They live in their own
--      table so that no join onto a profile can leak them by accident -- see
--      002_policies.sql, where nothing but the owner can read that table.
--   2. Pairing is mutual. One row *is* the pair, so a roster that exists in one
--      direction only cannot be represented.
--   3. Nobody learns who dismissed them. Dismissal is one-sided and private.
--   4. Location is coarse. The CHECK constraints refuse anything more precise
--      than the 0.01 grid, so a precise fix cannot be stored even by mistake.
--
-- Nothing in here records who looked at whom, when somebody was last online, or
-- whether a message was read. Those columns are absent on purpose: a column that
-- does not exist cannot be exposed in a later careless select.

create extension if not exists "uuid-ossp";


-- ---------------------------------------------------------------- enumerations
-- Mirrors of the Swift enums. Kept as native enums so a typo is a database error
-- rather than a row nobody notices.

create type gender          as enum ('man', 'woman', 'non_binary');
create type account_status  as enum ('active', 'paused', 'removed');
create type photo_state     as enum ('pending', 'approved', 'rejected');
create type conversation_state as enum ('request', 'open', 'ended');
create type delivery_state  as enum ('sending', 'sent', 'failed');
create type removal_reason  as enum ('abuse', 'photos', 'underage', 'selling', 'other');
create type removal_kind    as enum ('removed', 'paused', 'device');
create type appeal_state    as enum ('none', 'submitted', 'reviewed');
create type report_state    as enum ('new', 'reviewing', 'actioned', 'dismissed');


-- -------------------------------------------------------------------- accounts

-- The account itself. One row per Apple ID, forever.
create table accounts (
    id              uuid primary key references auth.users(id) on delete cascade,

    -- Apple's stable subject for this app. This is what a ban hangs on: it
    -- survives deleting the app, and you cannot work backwards from it to a
    -- person.
    apple_user_id   text not null unique,

    -- Apple sends these on the *first* authorization only. If they are not
    -- persisted then, they are gone for good -- which is the single most common
    -- way this integration is got wrong.
    apple_email     text,
    apple_name      text,

    status          account_status not null default 'active',
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),

    -- Set when the account is deleted. The row survives so that the Apple id
    -- stays claimed and a removed user cannot re-register by deleting first.
    deleted_at      timestamptz
);

-- Devices an account has attested from.
--
-- App Attest proves the request came from an unmodified build of this app on real
-- Apple hardware. It does not survive a reinstall, so it is no use for
-- recognising somebody coming back -- that is DeviceCheck's two bits, below.
create table account_devices (
    id                  uuid primary key default uuid_generate_v4(),
    account_id          uuid not null references accounts(id) on delete cascade,

    -- App Attest key, one per installation. The public key lives here after the
    -- server has verified the attestation against Apple's root.
    attest_key_id       text not null,
    attest_public_key   bytea not null,
    -- Must increase on every assertion. A counter that goes backwards is a replay.
    attest_counter      bigint not null default 0,

    first_seen          timestamptz not null default now(),
    last_seen           timestamptz not null default now(),

    unique (attest_key_id)
);

-- The two bits Apple keeps per device, across app deletion.
--
-- Stored separately from `account_devices` because the whole point is that it
-- outlives the account: when somebody removed comes back on the same phone, this
-- is the only row still standing.
--
--   bit1 -- banned. A hard block at signup.
--   bit0 -- this device has made an account before. A *soft* signal only:
--           flag for review, rate limit, never refuse. Households share iPads and
--           people legitimately start again.
create table device_bits (
    device_hash     text primary key,
    banned          boolean not null default false,
    has_registered  boolean not null default false,
    first_seen      timestamptz not null default now(),
    last_seen       timestamptz not null default now(),
    note            text
);


-- -------------------------------------------------------------------- profiles

-- What another person sees, and nothing else.
create table profiles (
    account_id      uuid primary key references accounts(id) on delete cascade,

    name            text not null check (length(trim(name)) between 1 and 40),

    -- Birthdate rather than age, so age is right tomorrow as well as today.
    -- Age is computed on read; it is never stored.
    birthdate       date not null,

    gender          gender not null,
    -- Free text and optional. Shown as written.
    pronouns        text check (pronouns is null or length(pronouns) <= 40),

    -- The picked place, from the app's library. Free-text neighbourhoods were
    -- removed because the distance filter had nothing to work with.
    place_id        text not null,

    -- Coarsened to 0.01 degrees, a little over a kilometre, *before* it arrives
    -- here. The precise fix a phone hands over is used to pick the square and then
    -- thrown away. These CHECKs make that a rule rather than a habit.
    coarse_lat      numeric(8, 2) not null
                    check (coarse_lat between -90 and 90
                           and coarse_lat = round(coarse_lat, 2)),
    coarse_lon      numeric(9, 2) not null
                    check (coarse_lon between -180 and 180
                           and coarse_lon = round(coarse_lon, 2)),

    height_cm       smallint check (height_cm between 120 and 230),
    work            text check (work is null or length(work) <= 60),

    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),

    -- Eighteen is a hard floor and belongs in the schema, not only in a form.
    constraint adult check (birthdate <= (current_date - interval '18 years'))
);

create index profiles_place_idx on profiles (place_id);
-- The nightly job scans by location; a plain btree on the pair is enough at this
-- scale and avoids taking a PostGIS dependency for one distance test.
create index profiles_coarse_idx on profiles (coarse_lat, coarse_lon);

create table photos (
    id              uuid primary key default uuid_generate_v4(),
    account_id      uuid not null references accounts(id) on delete cascade,
    -- 0-5. Position 0 is the one shown first.
    position        smallint not null check (position between 0 and 5),
    -- Object key in the storage bucket. The bucket is private; reads go through
    -- signed URLs so a photo cannot be hotlinked once somebody is blocked.
    storage_path    text not null,
    state           photo_state not null default 'pending',
    -- Set when state becomes 'rejected', shown to the owner so the screen can say
    -- what to do rather than only that something is wrong.
    rejected_reason text,
    created_at      timestamptz not null default now(),

    unique (account_id, position)
);

create table profile_prompts (
    id              uuid primary key default uuid_generate_v4(),
    account_id      uuid not null references accounts(id) on delete cascade,
    -- 0-2. Three, chosen by the user from the library during onboarding.
    position        smallint not null check (position between 0 and 2),
    prompt_key      text not null,
    answer          text not null check (length(trim(answer)) between 1 and 280),
    created_at      timestamptz not null default now(),

    unique (account_id, position)
);

create table profile_interests (
    id              uuid primary key default uuid_generate_v4(),
    account_id      uuid not null references accounts(id) on delete cascade,
    position        smallint not null,
    text            text not null check (length(trim(text)) between 1 and 40),

    unique (account_id, position)
);


-- ------------------------------------------------------- the private questions

-- **The table that must never leak.**
--
-- Sixteen answers: thirteen scored by the compatibility tables, three that filter.
-- They are the input to matching and they are shown to nobody, ever -- not to the
-- people you are paired with, not on your own profile.
--
-- Keeping them out of `profiles` is deliberate. If they were columns there, every
-- `select * from profiles` written in a hurry for the rest of the product's life
-- would be one review away from serialising them into a profile response. Here,
-- leaking them takes an explicit join that the policies refuse.
create table questionnaire_answers (
    account_id      uuid not null references accounts(id) on delete cascade,
    -- 'q1'..'q16', matching Questionnaire.swift.
    question_id     text not null check (question_id ~ '^q([1-9]|1[0-6])$'),
    -- Index into that question's options.
    option_index    smallint not null check (option_index between 0 and 5),
    answered_at     timestamptz not null default now(),

    primary key (account_id, question_id)
);


-- ------------------------------------------------------------------- discovery

create table discovery_settings (
    account_id      uuid primary key references accounts(id) on delete cascade,

    -- A requirement, not a preference: nobody outside it goes in a roster.
    seeking         gender[] not null default '{man,woman,non_binary}'
                    check (array_length(seeking, 1) >= 1),

    -- Miles. 100 means "Anywhere" and switches the distance filter off entirely
    -- rather than drawing a 100-mile circle -- see the matcher, where getting this
    -- wrong made a whole town unreachable.
    distance_miles  smallint not null default 10
                    check (distance_miles between 5 and 100),

    min_age         smallint not null default 26 check (min_age >= 18),
    max_age         smallint not null default 36 check (max_age <= 120),

    -- Nobody new arrives and you are in no roster. Conversations are untouched.
    paused          boolean not null default false,

    -- One switch, and it means one thing: a notification when somebody writes to
    -- you. There is nothing else to be notified about.
    notify_messages boolean not null default true,

    updated_at      timestamptz not null default now(),

    constraint age_order check (min_age <= max_age)
);

-- Premium: seven slots instead of five, fifteen conversations instead of ten.
-- It changes no ranking and nothing about who sees whom.
create table subscriptions (
    account_id          uuid primary key references accounts(id) on delete cascade,
    -- Apple's original_transaction_id -- the identifier that survives renewals.
    apple_original_txn  text not null unique,
    expires_at          timestamptz not null,
    updated_at          timestamptz not null default now()
);


-- --------------------------------------------------------------------- pairing

-- One row is one pair, in both directions at once.
--
-- This is the mutual-pairing rule made structural: there is no way to write a row
-- that puts A in B's roster without putting B in A's, because there is only the
-- one row. The ordering constraint keeps it unique.
create table pairings (
    id              uuid primary key default uuid_generate_v4(),
    -- The batch this belongs to. One global batch per day, on New York time.
    night           date not null,

    lo_account      uuid not null references accounts(id) on delete cascade,
    hi_account      uuid not null references accounts(id) on delete cascade,

    -- Kept for tuning the matcher, never sent to a client. Arch shows no
    -- percentages, no ranks and no badges; a score on the wire is a score that
    -- ends up on screen eventually.
    score           real,

    created_at      timestamptz not null default now(),

    constraint ordered check (lo_account < hi_account),
    unique (night, lo_account, hi_account)
);

create index pairings_lo_idx on pairings (lo_account, night desc);
create index pairings_hi_idx on pairings (hi_account, night desc);

-- One-sided and private.
--
-- If dismissing somebody removed you from their roster too, they would learn they
-- had been dismissed the moment you did it. So this opens the dismisser's slot and
-- leaves the other person's roster exactly as it was. Nobody is ever told.
create table dismissals (
    account_id      uuid not null references accounts(id) on delete cascade,
    other_account_id uuid not null references accounts(id) on delete cascade,
    night           date not null,
    created_at      timestamptz not null default now(),

    primary key (account_id, other_account_id, night)
);

-- Who has already been shown to whom, so the nightly job does not repeat people.
--
-- The matcher found this is also the main cause of anybody being left with an
-- empty roster: never repeating is a guarantee that runs out of people in a thin
-- pool. The window is a tuning knob, which is why it is a date and not a flag.
create table encounters (
    account_id      uuid not null references accounts(id) on delete cascade,
    other_account_id uuid not null references accounts(id) on delete cascade,
    last_night      date not null,

    primary key (account_id, other_account_id)
);


-- --------------------------------------------------------------- conversations

-- Messaging is the positive action: there are no likes and no match gate, and
-- writing to somebody spends a slot at both ends.
create table conversations (
    id              uuid primary key default uuid_generate_v4(),
    lo_account      uuid not null references accounts(id) on delete cascade,
    hi_account      uuid not null references accounts(id) on delete cascade,

    -- 'request'  -- one person has written, the other has not answered
    -- 'open'     -- both have
    -- 'ended'    -- see below
    state           conversation_state not null default 'request',

    -- Who opened it. Needed to know whose side is waiting; never shown as a label.
    opened_by       uuid not null references accounts(id) on delete cascade,

    created_at      timestamptz not null default now(),
    last_message_at timestamptz,

    constraint ordered check (lo_account < hi_account),
    unique (lo_account, hi_account)
);

-- **'ended' is one state on purpose.**
--
-- Leaving a conversation, blocking somebody, and deleting your account must all
-- produce a byte-identical result for the other person. If ending looked different
-- from blocking, the difference would name which one happened -- which is exactly
-- what the person on the other end must not be able to work out.
comment on column conversations.state is
    'ended covers leaving, blocking and account deletion alike: they must be indistinguishable to the other party.';

create table messages (
    id              uuid primary key default uuid_generate_v4(),
    conversation_id uuid not null references conversations(id) on delete cascade,
    sender_id       uuid not null references accounts(id) on delete cascade,
    body            text not null check (length(body) between 1 and 4000),
    created_at      timestamptz not null default now()

    -- No read_at, no delivered_at, no edited_at. Delivery is confirmed to the
    -- sender by the row existing; whether the other person has *read* it is
    -- theirs, and Arch does not collect it.
);

create index messages_conversation_idx on messages (conversation_id, created_at);

-- Device tokens for APNs. One notification exists: somebody wrote to you.
create table push_tokens (
    id              uuid primary key default uuid_generate_v4(),
    account_id      uuid not null references accounts(id) on delete cascade,
    token           text not null unique,
    updated_at      timestamptz not null default now()
);


-- ---------------------------------------------------------------------- safety

-- Never exposed to the blocked person, in any form, including by absence.
create table blocks (
    blocker_id      uuid not null references accounts(id) on delete cascade,
    blocked_id      uuid not null references accounts(id) on delete cascade,
    created_at      timestamptz not null default now(),

    primary key (blocker_id, blocked_id),
    constraint not_self check (blocker_id <> blocked_id)
);

create table reports (
    id              uuid primary key default uuid_generate_v4(),
    reporter_id     uuid not null references accounts(id) on delete set null,
    reported_id     uuid not null references accounts(id) on delete cascade,
    reason          removal_reason not null,
    note            text check (note is null or length(note) <= 1000),
    state           report_state not null default 'new',
    created_at      timestamptz not null default now(),
    -- Set by a human. Nothing here is actioned automatically.
    reviewed_at     timestamptz,
    reviewer_note   text
);

create index reports_reported_idx on reports (reported_id, created_at desc);

create table removals (
    id              uuid primary key default uuid_generate_v4(),
    account_id      uuid not null references accounts(id) on delete cascade,
    kind            removal_kind not null,
    reason          removal_reason not null,
    -- Set only for kind = 'paused'.
    until           timestamptz,
    created_at      timestamptz not null default now()
);

create table appeals (
    id              uuid primary key default uuid_generate_v4(),
    removal_id      uuid not null references removals(id) on delete cascade,
    body            text not null check (length(body) between 1 and 1000),
    state           appeal_state not null default 'submitted',
    created_at      timestamptz not null default now(),
    reviewed_at     timestamptz,

    -- One appeal per removal. A second is not a second chance.
    unique (removal_id)
);


-- --------------------------------------------------------- covering the keys
--
-- Postgres needs an index on the referencing side to check a foreign key when the
-- referenced row is deleted, and `delete_account` deletes down every one of these.
-- Without them that function degrades into a sequential scan per table.

create index if not exists account_devices_account_idx on account_devices (account_id);
create index if not exists blocks_blocked_idx on blocks (blocked_id);
create index if not exists conversations_hi_idx on conversations (hi_account);
create index if not exists conversations_opened_by_idx on conversations (opened_by);
create index if not exists dismissals_other_idx on dismissals (other_account_id);
create index if not exists encounters_other_idx on encounters (other_account_id);
create index if not exists messages_sender_idx on messages (sender_id);
create index if not exists push_tokens_account_idx on push_tokens (account_id);
create index if not exists removals_account_idx on removals (account_id);
create index if not exists reports_reporter_idx on reports (reporter_id);


-- ------------------------------------------------------------------- housekeeping

create or replace function touch_updated_at() returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

create trigger accounts_touch before update on accounts
    for each row execute function touch_updated_at();
create trigger profiles_touch before update on profiles
    for each row execute function touch_updated_at();
create trigger discovery_touch before update on discovery_settings
    for each row execute function touch_updated_at();
