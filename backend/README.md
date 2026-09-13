# Arch backend

Postgres on Supabase, plus the row-level security that keeps the product's
promises. Everything here runs fine from Windows.

## Files

| | |
|---|---|
| `001_schema.sql` | 20 tables, 9 enums, the constraints |
| `002_policies.sql` | RLS, 30 policies, and the `visible_profiles` view |
| `lint.py` | Cross-references the SQL without a database to run it against |

## Status

The database is **live and verified**: project `Arch App`, Postgres 17, all 20
tables, 36 policies, 18 of 18 security checks passing.

Running `004_rls_test.sql` against it found one real leak, now fixed. The `arch_*`
helper functions were in the `public` schema, and anything in `public` is also a
PostgREST endpoint -- so `/rest/v1/rpc/arch_blocked?a=X&b=Y` let any signed-in user
ask whether any two accounts had blocked each other. Every policy was correct and
the side door was open. They now live in a `private` schema, which PostgREST does
not expose; `authenticated` keeps EXECUTE because policy expressions are evaluated
as the querying user and the policies would fail without it.

Also fixed from the Supabase advisors: `auth.uid()` was being re-evaluated per row
across 26 policies (now `(select auth.uid())`), three `for all` policies were
overlapping the visibility policies on every read, and ten foreign keys had no
covering index -- which `delete_account` walks down every one of.

Two advisor warnings remain and are both intentional: `device_bits` has RLS on with
no policy (server-only by design), and `start_conversation` / `delete_account` are
callable by signed-in users (they are the API, and both check `auth.uid()` first).

## Setting the project up

**You have to do step 1 — it needs your account and your agreement to their
terms.** Everything after it is copy and paste.

**1. Create the project.** [supabase.com](https://supabase.com) → New project.
Pick a region near your users (`us-east-1` for New York). Save the database
password it gives you somewhere real; it is shown once.

**2. Apply the schema.** Dashboard → SQL Editor → New query. Paste
`001_schema.sql`, run it. Then the same for `002_policies.sql`. Order matters —
the policies reference the tables.

**3. Turn on Apple sign-in.** Authentication → Providers → Apple. You need, from
[developer.apple.com](https://developer.apple.com):

- your **Services ID** (the identifier you set up for Sign in with Apple)
- a **Sign in with Apple key** (`.p8`), plus its Key ID and your Team ID

Supabase verifies Apple's identity token for you with these, which is why the app
does not have to.

**4. Create the photo bucket.** Storage → New bucket → name it `photos`, and leave
**Public off**. Reads go through signed URLs, so that a photo stops being reachable
when somebody is blocked. A public bucket would keep serving it forever.

**5. Point the app at it — not yet possible.** This needs an `Info.plist`, which
arrives with the Xcode project, and there is no Xcode project in this repo. Keep
the two values somewhere safe until there is one; nothing reads them before then.

They live in Project Settings (the gear, bottom-left) → **API**: "Project URL" and
the `anon` / `public` key. Newer dashboards may file these under *API Keys* or
*Data API*, and may call the anon key "publishable". When the project exists they
go in as:

```xml
<key>ARCH_SUPABASE_URL</key>
<string>https://yourproject.supabase.co</string>
<key>ARCH_SUPABASE_ANON_KEY</key>
<string>eyJhbGci...</string>
```

The anon key is meant to ship inside the app — it identifies the project and
nothing else, and RLS decides every row it can reach. **The `service_role` key is
the opposite: it bypasses RLS entirely.** It belongs in edge functions and the
nightly job, and must never appear in the iOS target.

## Checking it before trusting it

Run `004_rls_test.sql` in the SQL Editor. It invents three people, has one of them
try to read everything they should not be able to, prints a PASS/FAIL table, and
**ends in ROLLBACK so nothing it creates survives** — safe to run against a
database with real rows in it.

This matters more than it looks. The SQL Editor normally runs as an admin who
bypasses RLS entirely, so everything looks readable in the dashboard whether the
policies work or not. Setting the role to `authenticated` with a jwt claim is the
only way these policies get exercised before a real phone does it.

There is no Postgres on this machine, so the SQL has never been executed.
`lint.py` is the partial answer:

```bash
python backend/lint.py
```

It cross-references every foreign key, column type, enum, policy target, index
column, trigger and view column, and checks RLS is enabled on all twenty tables.
**It proves the names resolve. It does not prove a policy is correct.**

That needs a real database and a deliberate attempt to read what should not be
readable. Once the project exists, make two accounts and check, as account B:

- [ ] B cannot read A's `questionnaire_answers` — **the one that matters most.**
      It should return zero rows, not an error.
- [ ] B cannot read A's `profiles` row when they are not paired and have no
      conversation
- [ ] B *can* read A's profile while they are paired
- [ ] B cannot read A's row in `dismissals`, whichever way the dismissal went
- [ ] B cannot read `device_bits` at all
- [ ] B cannot insert a row into `pairings`
- [ ] B cannot insert a message into a conversation whose state is `ended`
- [ ] B cannot read `reports`, including their own

A failure on the first line is the one that would matter. The questionnaire works
because people answer it honestly, and they answer it honestly because it is shown
to nobody.

## What the schema refuses to let you do

Four of Arch's promises are constraints rather than intentions:

**Questionnaire answers are a separate table with one owner-only policy.** As
columns on `profiles`, every `select *` written in a hurry would be one review away
from putting them on screen.

**A pairing is one row holding both directions**, with an ordering constraint. A
roster that exists in one direction cannot be represented.

**Dismissal is one-sided.** The policy keys on the dismisser alone, so the other
person cannot read the row, count rows, or be told.

**Coordinates are coarse by CHECK.** Anything off the 0.01 grid — about a
kilometre — is rejected, so a precise fix cannot be stored by mistake.

And `arch_in_conversation` deliberately excludes `ended`. Leaving, blocking and
deleting an account all land on that state, and all three have to look identical
from the other side; if a block took the profile away and leaving did not, the
difference would say which had happened.

## Still to build

- `functions/challenge` and `functions/register` — App Attest and the DeviceCheck
  ban check. Supabase Auth handles Apple; these handle everything else, and until
  they exist `device_bits` is a table nobody writes to.
- The nightly matcher, as `pg_cron` calling a function that ports
  `matcher/match.py`. One batch, 9am `America/New_York`.
- Photo moderation: the `pending` → `approved` path, and what the reader sees when
  it goes the other way.
