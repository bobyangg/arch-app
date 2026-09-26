# The public pages

Three static pages for the domain: `index.html` is the **Support URL**,
`privacy.html` the **Privacy Policy URL**, `terms.html` the terms. No scripts, no
external fonts, no trackers. A privacy policy that loaded one would be a strange
thing to publish.

**Drafts, not legal advice.** They were written from what the app and database
actually do (every processor, every field, what deletion removes and keeps),
which a template can't do. But have them read by someone qualified before launch.

## Before publishing

1. Replace every `[BRACKETED]` item: date, your name or company, city, contact
   email, mailing address (terms), retention days `[N]`.
2. `privacy.html` has two comments marked `TRUE-ONLY-AFTER`. Each describes
   deletion as it must work and **is not yet true of the live system**:
   - photo files are removed from storage when an account is deleted
   - the matcher's nightly snapshots are pruned after `[N]` days

   Fix both, or change the wording. Don't publish a promise the system doesn't
   keep.
3. Confirm whether profile notes (Claude) ship at launch. The privacy policy
   names Anthropic as a processor for that feature only.

## Hosting

Any static host works. Cloudflare Pages and GitHub Pages are both free:

- **Cloudflare Pages:** connect the repo, set the build output directory to
  `site`, no build command, then add your domain.
- **GitHub Pages:** it serves from `/docs` or the root, not `/site`, so either
  move these files or publish them from a small separate repo.

## Then, in the app

Set `ArchConfig.privacyURL`, and `ArchConfig.termsURL` once these terms replace
Apple's standard EULA, in `Arch/Backend/ArchConfig.swift`. The Premium screen
shows its links from those two values, and Apple rejects an auto-renewing
subscription without them.
