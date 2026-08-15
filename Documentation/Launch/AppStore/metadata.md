# Crest App Store listing packet

Prepared: 2026-08-09
App record: `6797335023`
Bundle ID: `com.pauldavis.crest`
Platforms: iOS and iPadOS
Release state: metadata preparation only—do not attach a build, add for review,
submit, or release.

This packet is the source of truth for Crest's first App Store product page.
It deliberately avoids competitor names in App Store metadata while carrying
the product site's native, Space-first positioning into the store.

## App information

| Field | Value |
| --- | --- |
| Name | `Crest Browser` |
| Subtitle | `Spaces. Native everywhere.` |
| Primary category | Utilities |
| Secondary category | Productivity |
| Content-rights posture | Crest is a general-purpose browser and can access third-party web content chosen by the user. Complete Apple's rights declaration from the browser context; do not imply that Crest supplies or owns that content. |
| Age-rating posture | Not made for kids. Declare unrestricted web access because Crest is a general-purpose browser; answer all content-frequency questions from the app itself rather than from arbitrary sites users may visit. |
| Copyright | `2026 Paul Davis` |

Character checks:

- Name: 13 of 30 characters
- Subtitle: 26 of 30 characters

## URLs

| Field | URL |
| --- | --- |
| Marketing URL | <https://pauljoda.github.io/Crest-Website/> |
| Support URL | <https://pauljoda.github.io/Crest-Website/> |
| Privacy-policy URL | <https://pauljoda.github.io/Crest-Website/privacy/> |

The product site already provides the field guide, TestFlight link, community
support route, and privacy policy. A dedicated `/support/` page is prepared in
the website source and should replace the temporary product-site Support URL
after that page is deployed.

## Version information

Use the same metadata for iPhone and iPad unless a platform-specific field is
called out. Crest for Mac is distributed directly and is not part of this App
Store submission packet.

### Promotional text

> A calmer browser built around truly separate Spaces—each with its own tabs,
> history, cookies, passwords, and personality—native on Mac, iPad, and iPhone.

### Description

> Crest is a native browser built around Spaces: distinct places for work,
> personal life, private browsing, and everything between.
>
> Each Space carries its own sidebar, tabs, history, cookies, website data,
> passwords, permissions, extensions, and visual identity. Switch Spaces and
> the whole browsing context moves with you—so accounts and projects stay where
> they belong.
>
> SPACES, PROPERLY SEPARATED
>
> A Space is more than a tab group or color. Crest gives every Space an
> isolated WebKit data store, Keychain boundary, history, permissions, and
> extension context. Private Spaces use temporary website storage and stay out
> of ordinary history, restoration, archive, and sync.
>
> A CALMER SIDEBAR
>
> Keep favorites, saved folders, pinned pages, and today’s tabs in one focused
> sidebar. Collapse a project when it is quiet, keep the page primary, and
> reach history, downloads, and archive without turning browsing into window
> management.
>
> NATIVE ON EVERY SCREEN
>
> Crest is purpose-built for Mac, iPad, and iPhone. Mac and iPad keep the
> sidebar beside the page. iPhone gives the page the full screen and brings the
> same sidebar back with a gesture. Familiar platform controls, keyboard
> shortcuts, menus, drag and drop, and system services stay at home on every
> device.
>
> MAKE EACH SPACE YOURS
>
> Choose a crest, palette, and banner for a bold identity, or use a quieter
> traditional gradient. A Space’s appearance is not decoration alone—it is an
> immediate signal that your accounts, data, and tabs changed with it.
>
> QUICK LOOKS, NOT TAB DETOURS
>
> Open supported links in Peek for a temporary look without losing your place.
> Move the page into the current Space or another Space only when it deserves
> to stay.
>
> MOVE IN WITHOUT STARTING OVER
>
> On Mac, Crest can import supported tabs, bookmarks, folders, profiles or
> Spaces, and passwords from supported browsers. Review the result Space by
> Space before anything is added.
>
> YOUR BROWSING STAYS YOURS
>
> Crest has no account system, advertising SDK, analytics pipeline, or
> browsing-data backend. Optional sync uses your private iCloud database.
> Passwords stay in the system Keychain, and private browsing remains
> temporary.
>
> Crest uses Apple’s WebKit and requires iOS 26.1, iPadOS 26.1, or macOS 26.1
> or later. Some websites, extensions, import sources, and system integrations
> vary by platform.

### Keywords

`spaces,tabs,tab manager,sidebar,private browsing,bookmarks,passwords,web,focus,productivity`

The keyword value must remain below App Store Connect's 100-byte limit. Do not
repeat the app name or category names merely to fill space.

## App privacy

Recommended draft, subject to a final dependency and network audit of the exact
build selected for submission:

- Tracking: **No**
- Data used for third-party advertising: **No**
- Data linked across third-party apps or websites: **No**
- Data collected by the developer or integrated third-party partners: **No**

Rationale:

- Crest has no developer account, analytics, advertising, attribution, or
  crash-reporting SDK.
- Open-web traffic does not need to be declared as developer collection under
  Apple's app-privacy guidance for apps that let users navigate the open web.
- Optional CloudKit and iCloud Keychain behavior uses Apple services associated
  with the user's account; Crest does not operate a parallel browsing-data
  service.
- On-device history, website data, passwords, and permissions are not
  developer collection.

App Store Connect's final **Publish** confirmation is a legal attestation. Save
the privacy-policy URLs and draft answers, but leave the final Publish action
for the account holder after auditing the selected build.

## App Review information

### Sign-in

Sign-in required: **No**. Crest has no Crest account and the review path must
work without an Apple ID or website credentials.

### Contact

Use the account holder's real first name, last name, phone number, and email.
Reuse the verified values already saved in App Store Connect; do not invent or
commit private contact data.

### Review notes

> Crest is a native general-purpose web browser built with Apple's WebKit. No
> Crest account, subscription, server, VPN, or sign-in is required.
>
> Suggested review path on iPhone or iPad:
>
> 1. Complete the short setup flow. Import is optional and can be skipped.
> 2. Open a website, create several tabs, and open the sidebar.
> 3. Use the Space picker at the top of the sidebar to move between Work and
>    Personal. Each Space has its own tabs, history, cookies, passwords,
>    permissions, and WebKit data store.
> 4. Open Settings → Spaces to inspect the per-Space crest, banner or gradient,
>    palette, and identity preview.
> 5. Open the Private Space to verify temporary browsing that does not join
>    ordinary history, restoration, archive, or synchronization.
>
> Crest does not use an alternative browser engine. Some websites, extensions,
> import sources, and system integrations vary by platform.

## Screenshot order

Every screenshot uses a real Crest capture from the product-site fixture set.
The rendered files add only branded framing and explanatory copy; they do not
simulate product controls.

### iPhone 6.5-inch — 1242 × 2688 portrait

1. Every Space is its own browser — the complete isolated sidebar model
2. The page stays primary — full-screen browsing with compact chrome
3. Make every Space unmistakable — Space identity and appearance controls
4. Move between worlds — visibly distinct Work and Personal Spaces
5. Tabs that stay organized — favorites, folders, saved tabs, and current tabs
6. Private by architecture — the boundaries that change with a Space

### iPad 13-inch — 2064 × 2752 portrait

1. One browser, two calm panes — sidebar and page working together
2. Work and personal stay apart — a visibly different browsing context
3. Make every Space unmistakable — native iPad settings and live preview
4. Your sidebar stays in sight — persistent project and tab organization
5. A whole browser moves with you — account and data boundaries per Space
6. Designed for the screen in your hands — native iPad layout

The renderer verifies exact pixel dimensions, clipped marketing copy, and
Apple's 10 MB screenshot limit before writing each file.

## Live App Store Connect status

Completed and saved on 2026-08-09:

- iOS 1.0 metadata, App Review contact and notes, no-sign-in review path, and
  manual release;
- six iPhone 6.5-inch screenshots and six iPad 13-inch screenshots;
- app subtitle, Utilities primary category, and Productivity secondary
  category;
- age-rating questionnaire with unrestricted web access and no app-supplied
  mature content, producing Apple's calculated 16+ rating;
- privacy-policy URL and a saved **Data Not Collected** privacy draft.

The live Support URL remains the deployed product-site root. Replace it with
the dedicated `/support/` route after the website changes in this commit are
deployed.

Still intentionally incomplete:

- no build is attached;
- App Privacy is saved as a draft but not published;
- content-rights and other legal attestations are not accepted;
- accessibility claims need a focused audit of the final build;
- price and territory availability need a product decision;
- the mobile version has not been added for review or submitted.

## Submission boundary

Metadata completion is not authorization to:

- attach or select a build;
- add the version for review;
- publish App Privacy answers;
- accept content-rights, export, or legal attestations;
- submit the app;
- schedule, manually release, or automatically release a version.

Stop with fields and screenshots saved, then hand the account holder the
remaining build-selection and submission actions.
