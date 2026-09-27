# App Store submission

Everything App Store Connect asks for that is words rather than switches, drafted
from what the app actually does. Copy from here; edit freely. Character limits are
Apple's.

---

## Listing

**Name** (30): `Arch Dating` — already registered to `com.arch.arch`.

**Subtitle** (30): `Five people, held. No swiping.` — exactly 30.

**Promotional text** (170, editable without a new build):

> Each morning, a few people chosen for you, and you are in their roster as they
> are in yours. No likes, no swiping, no queue. If you want to talk, you write.

**Description** (4000):

> Arch is a dating app built around one idea: fewer people, taken seriously.
>
> FIVE PEOPLE, HELD
> Every morning Arch introduces you to five people (seven with Premium). They stay.
> There is no queue to work through and nothing to clear. If you do nothing, they
> are still there tomorrow.
>
> MUTUAL BY DESIGN
> If someone is in your five, you are in theirs. Nobody ends up in a thousand
> rosters while someone else is in none.
>
> NO MATCH STEP
> Nobody has to like you back before you can write. If you want to talk to
> someone, you write to them. That is the whole mechanism.
>
> NOTHING TO READ INTO
> No read receipts, no "seen", no online dots, no percentages. Arch never tells you
> who dismissed you or why a slot opened. You are never told you were ranked,
> because you are not.
>
> A QUESTIONNAIRE THAT STAYS PRIVATE
> Sixteen short questions decide who reaches your five. Your answers are never on
> your profile and never shown to anyone.
>
> ARCH PREMIUM
> Seven people instead of five, room for more conversations, and your town set
> wherever you like. Premium changes how many people you meet, never who Arch
> chooses or anything about who has looked at you.
>
> Premium is an auto-renewing subscription. Payment is charged to your Apple ID at
> confirmation, and it renews at the same price unless cancelled at least 24 hours
> before the end of the period. Manage or cancel it in your Apple ID settings.
>
> Terms: [DOMAIN]/terms.html · Privacy: [DOMAIN]/privacy.html
>
> Arch is for adults 18 and over.

**Keywords** (100, commas, no spaces): check the count after editing.

```
dating,date,singles,relationship,meet,slow dating,no swipe,serious,partner,love,introductions
```

**URLs**
- Support URL: `https://[DOMAIN]/`
- Privacy Policy URL: `https://[DOMAIN]/privacy.html`
- Marketing URL: optional; the same as support is fine.

**Category:** Lifestyle (primary). Social Networking (secondary) is also defensible.

**Screenshots:** the largest iPhone size Apple currently requires. Roster, a
profile, a conversation, Premium. Use test accounts with consented photos; never
real users' faces.

---

## App Privacy (the "nutrition label")

Arch does **not** track: no third-party advertising or analytics SDKs, and no data
shared with data brokers. Answer **No** to tracking.

Everything below is **linked to the user's identity**. Purpose is **App
Functionality** unless noted.

| Apple's category | Data type | What it is in Arch |
|---|---|---|
| Contact Info | Name | First name on the profile; Apple name if shared |
| Contact Info | Email Address | Apple relay or real email; email sign-in |
| Location | Coarse Location | Rounded to about 1 km, once, for distance matching |
| Sensitive Info | Sensitive Info | Who you are looking for can imply sexual orientation |
| User Content | Photos or Videos | Profile photographs |
| User Content | Emails or Text Messages | In-app messages |
| User Content | Other User Content | Prompts, interests, questionnaire answers |
| Identifiers | User ID | Account id |
| Identifiers | Device ID | App Attest / DeviceCheck. Purpose: App Functionality (fraud prevention) |
| Purchases | Purchase History | Premium subscription status |
| Usage Data | Product Interaction | Dismissals, blocks, reports, who you wrote to. Purposes: App Functionality **and Analytics** (the pseudonymous introduction record used to evaluate the matcher) |
| Other Data | Other Data Types | Date of birth, gender, pronouns, height, work |

If profile notes (Claude) are enabled at launch, photos and prompts are also sent to
Anthropic when the user asks. That is a service provider acting for Arch, not
"third-party use", but it belongs in the privacy policy, which says so.

---

## Age rating

Answer the questionnaire honestly and expect **18+**. The app itself refuses
anyone under 18 at onboarding (`Birthday.minimumAge`). It has messaging and
user-generated content, which the questionnaire asks about directly.

---

## Review notes

Paste into App Review Information → Notes, and fill in the demo account.

> Arch is a dating app with a deliberately different mechanic, which may not be
> obvious in a short review:
>
> - There is no swiping and no "like". Each morning (9am New York) Arch builds a
>   roster of five people per user. Pairing is mutual: if A is in B's roster, B
>   is in A's. Writing to someone is the only positive action.
> - Because rosters are built overnight, a brand-new account has an empty roster
>   until the next morning. The demo account below already has people in it.
>
> Demo account (sign in with email → enter the address → the code is emailed to
> an inbox we monitor): [DEMO EMAIL]. [OR: explain how the reviewer gets the code.]
>
> Where to find the required features:
> - Report and block: any profile or conversation → ⋯ menu.
> - Delete account: Settings → Delete account (immediate).
> - Terms and Privacy: under the subscribe button on the Premium tab, and in
>   Settings.
> - Premium: the Premium tab. Purchases use the sandbox.
>
> Minimum age is 18, enforced at onboarding from the date of birth.

The demo account needs **email sign-in to work**, which needs a real sending
service (Supabase's built-in email is rate-limited and not for production). That
is the domain task, and it is on the critical path for review.

---

## Known review risks

- **Guideline 1.2 (user-generated content)** requires reporting, blocking, a
  published contact, *and a method for filtering objectionable material*. Arch has
  the first three. **It has no filter:** photographs approve themselves the moment
  they finish uploading (`approve_on_upload`), and moderation only happens after a
  report. A dating app is exactly where a reviewer checks this. The cheapest
  credible fix is on-device nudity detection before upload with Apple's
  SensitiveContentAnalysis framework (iOS 17+), plus the manual review that
  already exists.
- **Guideline 4.3 (saturated categories).** Dating is one. The review notes above
  lead with what is different for that reason.
- **Guideline 5.1.1(ix).** Apps handling sensitive data are expected to come from
  a legal entity. Arch ships from an individual account. Some dating apps pass as
  individuals and some do not; if it is rejected on this, the answer is an
  Organization account, which needs incorporation and a D-U-N-S number.
- **Guideline 5.1.1(v).** Deleting an account must delete its data. Photo files
  now are: an hourly sweep removes any file with no photo row (the first run
  removed 56). Still open: the matcher's nightly snapshots (`match_people`,
  `match_edges`, `match_state`) survive account deletion, keyed by account id.
  The privacy policy marks that sentence.
