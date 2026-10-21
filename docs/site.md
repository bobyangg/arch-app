# The public pages (`site/`)

Kept here rather than in `site/`, because everything in `site/` is uploaded and published -- this file included, if it were there.

Static pages for archdating.com. No scripts, no third-party fonts, no trackers.
A privacy policy that loaded one would be a strange thing to publish.

| Page | What it is |
|---|---|
| `index.html` | Home. Also works as the App Store **Support URL**: Help is in the header, the email in the footer |
| `how-it-works.html` | Every rule, the sixteen questions, the Date planner, Premium |
| `about.html` | About us: why five, why no likes, why the name, what we won't do |
| `safety.html` | Opened by the app's Settings → Safety row (`ArchConfig.safetyURL`) |
| `help.html` | FAQ and contact; could be the Support URL instead of the home page |
| `privacy.html` | The **Privacy Policy URL** |
| `terms.html`, `terms-fr.html` | The terms, and their French version |
| `404.html` | Served for a missing page; its links start at `/` so it works at any address |

## How it is made

**From the app's own design system**, so the site and the app read as one thing:
the `ArchColor` palette in both appearances (the site follows the reader's light
or dark setting), the app's three typefaces served from `site/fonts/` (trimmed to
Latin, French accents included; the OFL licences sit beside them), its corner
radii, and its rules -- sentence case, no all-caps labels, no drop shadows. The
mark and the five stones are drawn from the same geometry as `ArchMark` and
`ArchBand`, and the phones on the home page are the app's screens drawn in HTML,
with photographs drawn from the quarry materials the app's design build uses.

**Nothing on it is invented.** The copy is what the app does: its rules, its
sixteen questions, its Settings rows. The profiles and the conversation are
labelled as examples. There are no testimonials, press logos or user counts;
add real ones when there are some.

**Editing.** Each page is plain HTML. The header and footer are repeated in every
page, so a change to either is a find-and-replace across all nine. Everything
shared lives in `site.css`. `og.png` is the picture shown when a link is shared,
and `favicon.svg` / `apple-touch-icon.png` are the tab and home-screen icons.

**Before launch:** the "Join the beta" buttons are `mailto:` links asking for a
TestFlight invitation. When Arch is on the App Store, point them at its listing.

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

When you upload a changed `site/` folder, drag the whole folder in again --
including `fonts/`. Each upload replaces everything, so one page on its own
takes the rest down.
