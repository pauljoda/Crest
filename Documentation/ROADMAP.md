# Crest roadmap

This file summarizes public release outcomes and work that is still outstanding
or intentionally deferred. The live
[Crest Roadmap project](https://github.com/users/pauljoda/projects/3) shows
status; release milestones hold the actionable issue descriptions.

<!-- crest-roadmap-sync:start -->
## Active releases

Release milestones are shown from earliest to latest. The project board holds
the live status for each issue.

### [0.5](https://github.com/pauljoda/Crest/milestone/1)

#### Planned and in progress

- [ ] [Add global sidebar widgets for updates and media](https://github.com/pauljoda/Crest/issues/4)
- [ ] [Support video picture-in-picture and optional automatic PiP](https://github.com/pauljoda/Crest/issues/6)
- [ ] [Add an About section for build, updates, and community links](https://github.com/pauljoda/Crest/issues/7)
- [ ] [Add native emoji picking to icon customization](https://github.com/pauljoda/Crest/issues/9)
- [ ] [Let people choose custom search engines](https://github.com/pauljoda/Crest/issues/13)
- [ ] [Import passwords from standard browser exports](https://github.com/pauljoda/Crest/issues/16)
- [ ] [Refine split-view groups with editable names, icons, and tint](https://github.com/pauljoda/Crest/issues/17)
- [ ] [Offer optional search suggestions in the command palette](https://github.com/pauljoda/Crest/issues/19)
- [ ] [Add a default page zoom setting](https://github.com/pauljoda/Crest/issues/20)
- [ ] [Investigate Google Drive pages that remain blurred](https://github.com/pauljoda/Crest/issues/26)
- [ ] [Restore navigation history when reopening archived tabs](https://github.com/pauljoda/Crest/issues/30)
- [ ] [Keep native window controls reachable in full screen](https://github.com/pauljoda/Crest/issues/31)
- [ ] [Improve download progress and access](https://github.com/pauljoda/Crest/issues/34)
- [ ] [Keep split-view groups visible in collapsed folders](https://github.com/pauljoda/Crest/issues/35)
- [ ] [Preserve navigation when content blocking redirects](https://github.com/pauljoda/Crest/issues/36)

#### Completed

- [x] [Add website notification support with clear per-Space controls](https://github.com/pauljoda/Crest/issues/5) — [`116cecc8`](https://github.com/pauljoda/Crest/commit/116cecc871a8cd369ce567e93535fa5ff1c0ca01)
- [x] [Make the full sidebar adaptive across iPad and wider iPhone layouts](https://github.com/pauljoda/Crest/issues/8)
- [x] [Prevent synced pinned and saved tabs from disappearing](https://github.com/pauljoda/Crest/issues/14) — [`ba775bfe`](https://github.com/pauljoda/Crest/commit/ba775bfe1819db9b2d0792f8f3687309078d8a5e)
- [x] [Support website location permissions](https://github.com/pauljoda/Crest/issues/15) — [`116cecc8`](https://github.com/pauljoda/Crest/commit/116cecc871a8cd369ce567e93535fa5ff1c0ca01), [`986bee77`](https://github.com/pauljoda/Crest/commit/986bee77f3e4331c5ab0f619a225a6a8aa97d1b2)
- [x] [Improve download access and archive-menu behavior](https://github.com/pauljoda/Crest/issues/18)
- [x] [Keep the iPad layout stable with the floating keyboard](https://github.com/pauljoda/Crest/issues/21)
- [x] [Keep WebExtension background pages responsive after returning to Crest](https://github.com/pauljoda/Crest/issues/23) — [`465a4913`](https://github.com/pauljoda/Crest/commit/465a491331ab56fbec25ba6f7e861d0445fe0e9a)
- [x] [Let Quick Windows remain where users place them](https://github.com/pauljoda/Crest/issues/24) — [`9e19a244`](https://github.com/pauljoda/Crest/commit/9e19a24407f60b45863c9127e26782759b40c0c4)
- [x] [Preserve sign-in return flows in new browser windows](https://github.com/pauljoda/Crest/issues/25) — [`0c5d61c6`](https://github.com/pauljoda/Crest/commit/0c5d61c6f770a398859e8c8dd5de55f03aad250b)
- [x] [Show the Crest install action on localized Chrome Web Store pages](https://github.com/pauljoda/Crest/issues/27) — [`d62a26b7`](https://github.com/pauljoda/Crest/commit/d62a26b764d2cd387119c2eb7c2080498e890229)
- [x] [Make browser-import setup respect selections and source access](https://github.com/pauljoda/Crest/issues/28) — [`8c9d0f78`](https://github.com/pauljoda/Crest/commit/8c9d0f782b1e7cbbccd74f64cc1dfe4aeabd0b96)
- [x] [Expose native WebKit feature flags in macOS Settings](https://github.com/pauljoda/Crest/issues/37) — [`6a672260`](https://github.com/pauljoda/Crest/commit/6a6722600a378942afb381adaab6d7f9f6d1ac9f)

<!-- crest-roadmap-sync:end -->

These describe intended user outcomes rather than fixed implementation
promises. Scope may change when WebKit capability, accessibility, or physical
device evidence shows a better boundary.

## Approval-gated capabilities

- Obtain Apple's managed default-browser entitlement for `com.pauldavis.crest`, then enable and validate default-browser registration on physical devices.
- Complete the browser passkey entitlement request and physical-device passkey validation before advertising passkey-provider support.

## Release gates

- Deploy and verify the production CloudKit schema.
- Complete two-device convergence testing for Space lifecycle, secure deletion, Keychain behavior, and offline edits.
- Exercise camera, microphone, document picker, picture-in-picture, and offline recovery on physical iPhone and iPad hardware.
- Finish physical accessibility coverage for VoiceOver, Voice Control, keyboard-only use, pointer interaction, larger text, reduced motion, and right-to-left localization.
- Validate Stage Manager and external-display behavior on iPad.
- Run the real-world migration corpus for bookmarks, tabs, folders, and portable archives from supported source browsers.

## Active platform work

- Extension work is active on macOS. Preserve per-Space isolation, prefer Safari Web Extension app bundles where native integration is required, and report WebKit compatibility limits instead of presenting partially initialized extension UI as working.
