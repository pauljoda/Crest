# Crest roadmap

This file summarizes public release outcomes and work that is still outstanding
or intentionally deferred. The live
[Crest Roadmap project](https://github.com/users/pauljoda/projects/3) shows
status; release milestones hold the actionable issue descriptions.

## Published releases

- [Crest 0.6.3](https://github.com/pauljoda/Crest/releases/tag/v0.6.3) — [release scope and completed work](https://github.com/pauljoda/Crest/milestone/2?closed=1).
- [Crest 0.5.7](https://github.com/pauljoda/Crest/releases/tag/v0.5.7) — [release scope and completed work](https://github.com/pauljoda/Crest/milestone/1?closed=1).

<!-- crest-roadmap-sync:start -->
## Active releases

Release milestones are shown from earliest to latest. The project board holds
the live status for each issue.

### [0.7](https://github.com/pauljoda/Crest/milestone/3)

#### Planned and in progress

- [ ] [Investigate compatible browser extensions on iPhone and iPad](https://github.com/pauljoda/Crest/issues/53)
- [ ] [feature: Swipping Tab Gesture On iphone](https://github.com/pauljoda/Crest/issues/54)
- [ ] [feature: Decouple pinned tab options and regular tab options](https://github.com/pauljoda/Crest/issues/138)
- [ ] [Organize shared browsing sessions with Sub-Spaces](https://github.com/pauljoda/Crest/issues/144)
- [ ] [Choose a default Space using Focus](https://github.com/pauljoda/Crest/issues/145)
- [ ] [Separate selection outlines from tab highlight colors](https://github.com/pauljoda/Crest/issues/146)
- [ ] [Choose which browsing data syncs across devices](https://github.com/pauljoda/Crest/issues/149)
- [ ] [Add common browsing actions to the macOS Dock menu](https://github.com/pauljoda/Crest/issues/152)
- [ ] [Choose which sidebar widgets appear](https://github.com/pauljoda/Crest/issues/160)
- [ ] [Switch the active Space in a Quick Window](https://github.com/pauljoda/Crest/issues/161)
- [ ] [Dim only the content behind Peek](https://github.com/pauljoda/Crest/issues/164)
- [ ] [Stop LastPass popups from reloading the active page](https://github.com/pauljoda/Crest/issues/169)
- [ ] [Clear browsing data by Space and time range](https://github.com/pauljoda/Crest/issues/170)

#### Completed

- [x] [Keep active location access consistent with site permissions](https://github.com/pauljoda/Crest/issues/141)
- [x] [Keep extension compatibility access aligned with permission choices](https://github.com/pauljoda/Crest/issues/142) — [`22b22c95`](https://github.com/pauljoda/Crest/commit/22b22c959f59d9d1f7a6d7b490f14834fc446129)
- [x] [Clarify local extension replacement and permission continuity](https://github.com/pauljoda/Crest/issues/143) — [`361a1e92`](https://github.com/pauljoda/Crest/commit/361a1e92cd2652e21746e3e3376a54aad70f1c5b)
- [x] [Apply browser border size to Quick Windows](https://github.com/pauljoda/Crest/issues/147) — [`e2dd9187`](https://github.com/pauljoda/Crest/commit/e2dd9187d6a1345c5a1106726e64bdae012d67f0)
- [x] [Restore downloads from the built-in PDF preview](https://github.com/pauljoda/Crest/issues/150) — [`616f92d7`](https://github.com/pauljoda/Crest/commit/616f92d745b82c36cf78daded5e7174d83ab1669)
- [x] [Preserve webpage text interaction beneath the hidden title bar](https://github.com/pauljoda/Crest/issues/155) — [`9610550a`](https://github.com/pauljoda/Crest/commit/9610550a5690bbad15ef3bf37087c9dd085921b6)
- [x] [Make unloaded-tab dimming optional](https://github.com/pauljoda/Crest/issues/162) — [`b920e80e`](https://github.com/pauljoda/Crest/commit/b920e80e096087b26b67e98ff986dd54644ddb33)
- [x] [Investigate WebP conversion and Slack Huddle behavior](https://github.com/pauljoda/Crest/issues/163) — [`f0de6ca2`](https://github.com/pauljoda/Crest/commit/f0de6ca247b6a769941e70042564aeebb6592011)
- [x] [Return from picture-in-picture to the originating tab](https://github.com/pauljoda/Crest/issues/166) — [`0e5c7162`](https://github.com/pauljoda/Crest/commit/0e5c716267863df43256d7a0b5b2d007440288ff)
- [x] [Balance Quick Window Space indicator padding](https://github.com/pauljoda/Crest/issues/171)

#### Not planned

- [x] [Use a thinner scrollbar that fades when idle](https://github.com/pauljoda/Crest/issues/148)

<!-- crest-roadmap-sync:end -->

These describe intended user outcomes rather than fixed implementation
promises. Scope may change when WebKit capability, accessibility, or physical
device evidence shows a better boundary.

## Approval-gated capabilities

- Obtain Apple's managed default-browser entitlement for `com.pauldavis.crest`, then enable and validate default-browser registration on physical devices.
- Complete the browser passkey entitlement request and physical-device passkey validation before advertising passkey-provider support.

## Release gates

Repeat these checks for each release candidate.

- Deploy and verify the production CloudKit schema.
- Complete two-device convergence testing for Space lifecycle, secure deletion, Keychain behavior, and offline edits.
- Exercise camera, microphone, document picker, picture-in-picture, and offline recovery on physical iPhone and iPad hardware.
- Finish physical accessibility coverage for VoiceOver, Voice Control, keyboard-only use, pointer interaction, larger text, reduced motion, and right-to-left localization.
- Validate Stage Manager and external-display behavior on iPad.
- Run the real-world migration corpus for bookmarks, tabs, folders, and portable archives from supported source browsers.

## Active platform work

- [Image-conversion compatibility](https://github.com/pauljoda/Crest/issues/163) is delivered. Slack Huddles remain deferred and are not claimed fixed or validated.

- Extension work is active on macOS. Preserve per-Space isolation, prefer Safari Web Extension app bundles where native integration is required, and report WebKit compatibility limits instead of presenting partially initialized extension UI as working.
