# Edge functions

Four. The first two exist because Supabase Auth cannot do their job; the other
two because a phone should not hold an APNs key or an Anthropic key.

By the time any of them runs, Supabase has already verified Apple's identity token
against Apple's own keys and issued a session, so **who the caller is, is settled**.
These add the parts Supabase does not do.

| | |
|---|---|
| `challenge` | Issues a one-time nonce, tied to the signed-in user |
| `register` | Verifies attestation, checks the ban, creates the account |
| `push` | Drains the notification outbox to Apple. Called by pg_cron, not by the app |
| `review` | Notes on your own profile, from Claude. Premium; the Notes half of the review screen |
| `subscription` | The app bought or restored Premium: ask Apple, record the answer. Signed in |
| `app-store-notifications` | Apple, saying a subscription renewed, lapsed or was refunded. **No JWT** -- Apple has no session |
| `photo-sweep` | Removes photo files no photograph owns. Called hourly by `private.sweep_photos` with the push job's cron secret. Only the Storage API may delete a file; SQL is refused |
| `_shared/appattest.ts` | Apple's verification steps, in Apple's order |
| `_shared/devicecheck.ts` | The two bits, over Apple's server-to-server API |

## The review

`POST /functions/v1/review` with the words — `{name, age, work, prompts: [{question,
answer}], interests, fresh}`. The photographs are **not** in the request: the
function reads the caller's approved photos from the `photos` table and the private
bucket itself, so what the reviewer sees is what the profile shows.

It calls `claude-opus-5` once, with the photographs as images and a fixed JSON
schema for the answer — one note per photograph, one per answer, a paragraph
overall, each note carrying a verdict of `keep`, `consider` or `change`. The system
prompt is the important part: about the photograph as a photograph and the writing
as writing, never about the person, and the schema has no field for a score.

The answer is stored in `profile_reviews` against a digest of what was reviewed.
The same profile gets the same notes back without a second call; `fresh: true`
asks anyway, and fresh reviews are capped at five a day per account.

**Premium is checked and not yet enforced.** `subscriptions` is only ever written
after Apple verifies a receipt, and no server does that yet, so with
`PREMIUM_ENFORCED` unset the check logs that it was skipped and continues — the
same posture as `ATTEST_ENFORCED`. Set it to `true` once purchases exist.

## Premium

**Apple is asked, not believed.** Neither the app nor a notification is trusted
for what it says -- only for which transaction to go and ask about. The answer
comes from Apple's App Store Server API over TLS, in reply to a request signed
with the In-App Purchase key, so the transport authenticates it and there is no
certificate chain to verify here and get subtly wrong. A forged notification can
make the server re-check a real subscription and write down the truth. That is
all it can do.

`_shared/subscriptions.ts` is the only writer of `subscriptions`, and it decides
*whose* a purchase is from the `appAccountToken` the app attaches when it buys --
which Apple keeps on every renewal. A phone cannot restore a subscription onto an
account Apple says did not pay for it.

To switch it on, in App Store Connect:

1. **Subscriptions** -> one group, three auto-renewable products with exactly
   these ids: `com.arch.arch.premium.1m`, `com.arch.arch.premium.3m`,
   `com.arch.arch.premium.12m`. They are in `Purchases.catalogue` in the app.
2. **Users and Access -> Integrations -> In-App Purchase** -> generate a key. Set
   the three `APPSTORE_*` secrets below from it.
3. **App Information -> App Store Server Notifications** -> Version 2, and this
   URL for both Production and Sandbox:
   `https://<project>.supabase.co/functions/v1/app-store-notifications`
4. Once a sandbox purchase has come through, set `PREMIUM_ENFORCED=true`.

None of it can be tested -- not even in the sandbox -- until the **Paid
Applications agreement** is active. Until then the products do not load and the
Premium screen says Premium is not available yet, which is the truth.

## The exchange

1. App signs in with Apple → Supabase session
2. `POST /functions/v1/challenge` → a 32-byte nonce, stored server-side
3. App calls `Attestation.attest(challenge:)` → keyId + attestation object
4. `POST /functions/v1/register` with `{challenge, keyId, attestation, deviceToken, name, email}`
5. Server verifies, reads the DeviceCheck bits, creates the account

The challenge is the replay defence. Without it the whole exchange would prove
only that somebody, once, had a real iPhone.

## Secrets

Set these in Dashboard → Edge Functions → Secrets. None are set yet, and the
functions are written to work without them.

| | |
|---|---|
| `APPLE_TEAM_ID` | From your Apple developer account |
| `APP_BUNDLE_ID` | e.g. `com.yourname.arch` |
| `APPLE_DEVICECHECK_KEY_ID` | The `.p8` key's id |
| `APPLE_DEVICECHECK_KEY` | The `.p8` file's contents |
| `ATTEST_ENFORCED` | `true` to refuse unattested signups. Leave unset at first |
| `ANTHROPIC_API_KEY` | For `review`. Without it the function answers 503 and the screen says notes are not available |
| `PREMIUM_ENFORCED` | `true` to refuse reviews to accounts with no live subscription. Leave unset until purchases exist |
| `APPSTORE_ISSUER_ID` | Users and Access -> Integrations -> In-App Purchase: the issuer id at the top of the page |
| `APPSTORE_KEY_ID` | That key's id |
| `APPSTORE_KEY` | The `.p8` file's contents. A server credential: never in the app, never in the repo |

Without the DeviceCheck three, the ban check is skipped and a line is logged
saying so. That is the right default for a project with no Apple credentials yet —
the alternative is nobody being able to sign up at all — but **bans are
unenforceable until they are set**, and the log line exists so that is visible
rather than quietly true.

`ATTEST_ENFORCED` is separate on purpose. Turning attestation on and enforcing it
in the same change means the first failure is indistinguishable from every real
user being locked out. Run it unenforced, watch `accounts.attested_at` fill in on
real devices, then enforce.

## Verified

Deployed and exercised end to end against the live project with a throwaway
account, since deleted:

- `challenge` issues a nonce and stores it against the caller
- `register` creates the account, and a second call is idempotent
- **a second call does not overwrite `apple_name`** — Apple sends the name on the
  first authorization only, and overwriting it with a later null is the classic way
  to lose it forever
- a garbage attestation is not accepted (`attested: false`, no `account_devices` row)
- a spent challenge cannot be reused

What that does **not** prove: that a real attestation from a real iPhone verifies.
Nothing here has ever seen one. `_shared/appattest.ts` implements Apple's steps and
fails closed on every path, but the first genuine device is still the real test —
which is exactly what `ATTEST_ENFORCED=false` is for.

One deliberate compromise, marked in the source: Apple's App Attest root is fetched
at cold start rather than pinned in the file. Pinning is what Apple recommends. It
is fetched because a root certificate transcribed from memory would be worse than
either — subtly wrong, and failing as though every device were broken. Download it
once and paste it in before this carries real traffic.
