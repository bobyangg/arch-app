# Edge functions

Two, and they exist because Supabase Auth cannot do their job.

By the time either runs, Supabase has already verified Apple's identity token
against Apple's own keys and issued a session, so **who the caller is, is settled**.
These add the parts Supabase does not do: proof the request came from the real app
on real hardware, and the ban check.

| | |
|---|---|
| `challenge` | Issues a one-time nonce, tied to the signed-in user |
| `register` | Verifies attestation, checks the ban, creates the account |
| `_shared/appattest.ts` | Apple's verification steps, in Apple's order |
| `_shared/devicecheck.ts` | The two bits, over Apple's server-to-server API |

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
