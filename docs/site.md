# The public pages (`site/`)

Kept here rather than in `site/`, because everything in `site/` is uploaded and published -- this file included, if it were there.

Static pages for archdating.com: `index.html` is the **Support URL**,
`privacy.html` the **Privacy Policy URL**, `terms.html` the terms, and
`terms-fr.html` their French version. No scripts, no external fonts, no
trackers. A privacy policy that loaded one would be a strange thing to publish.

**Drafts, not legal advice.** The privacy policy was written from what the app and
database actually do (every processor, every field, what deletion removes and
keeps). The terms are the team's draft with its blanks filled in. Have both read
by someone qualified before launch -- the French translation and the line saying
the English version prevails especially.

## Where things stand

1. No blanks left in any page.
2. Deletion is as the privacy policy describes it: photo files are swept hourly, and the matcher's
   nightly snapshots are deleted with the account and cleared after 90 days (migration 022).
3. The terms say Arch is not offered in the United States or in Quebec. Keep the App Store
   availability to match: Canada only. Offering it in the US first needs the state dating-service
   notices that Schedule B2 promises.
4. The two terms pages mirror each other section for section. A change to one is a change to both.

## Hosting

Any static host works. Cloudflare Pages and GitHub Pages are both free:

- **Cloudflare Pages:** connect the repo, set the build output directory to
  `site`, no build command, then add your domain.
- **GitHub Pages:** it serves from `/docs` or the root, not `/site`, so either
  move these files or publish them from a small separate repo.

## In the app

`ArchConfig.termsURL`, `termsFrenchURL` and `privacyURL` point at the live pages
(the host drops `.html`, so the app links without it). Onboarding asks everybody to
accept the terms, and records the version in `terms_acceptances` (migration 023).
**When the terms change, change `ArchConfig.termsVersion` with them**, or new
acceptances are filed under the old version.

When you upload a changed `site/` folder, drag the whole folder in again.
