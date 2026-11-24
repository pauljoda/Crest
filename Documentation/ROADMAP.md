# Crest roadmap

This file summarizes public release outcomes and work that is still outstanding
or intentionally deferred. The live
[Crest Roadmap project](https://github.com/orgs/crest-browser/projects/1) shows
status; release milestones hold the actionable issue descriptions.

## Published releases

- [Crest 0.11.0](https://github.com/crest-browser/Crest/releases/tag/v0.11.0) — [release scope and completed work](https://github.com/crest-browser/Crest/milestone/7?closed=1).
- [Crest 0.10.24](https://github.com/crest-browser/Crest/releases/tag/v0.10.24) — [release scope and completed work](https://github.com/crest-browser/Crest/milestone/6?closed=1).
- [Crest 0.9.1](https://github.com/crest-browser/Crest/releases/tag/v0.9.1) — [release scope and completed work](https://github.com/crest-browser/Crest/milestone/5?closed=1).
- [Crest 0.8.50](https://github.com/crest-browser/Crest/releases/tag/v0.8.50) — [release scope and completed work](https://github.com/crest-browser/Crest/milestone/4?closed=1).
- [Crest 0.7.2](https://github.com/crest-browser/Crest/releases/tag/v0.7.2) — [release scope and completed work](https://github.com/crest-browser/Crest/milestone/3?closed=1).
- [Crest 0.6.3](https://github.com/crest-browser/Crest/releases/tag/v0.6.3) — [release scope and completed work](https://github.com/crest-browser/Crest/milestone/2?closed=1).
- [Crest 0.5.7](https://github.com/crest-browser/Crest/releases/tag/v0.5.7) — [release scope and completed work](https://github.com/crest-browser/Crest/milestone/1?closed=1).

<!-- crest-roadmap-sync:start -->
## Active releases

Release milestones are shown from earliest to latest. The project board holds
the live status for each issue.

### [0.12](https://github.com/crest-browser/Crest/milestone/8)

#### Planned and in progress

- [ ] [Reveal the collapsed iPad sidebar on pointer hover](https://github.com/crest-browser/Crest/issues/176)
- [ ] [feature: Add Edit Pinned URL menu option and dialogue](https://github.com/crest-browser/Crest/issues/218)
- [ ] [feature: Double-click a tab to rename](https://github.com/crest-browser/Crest/issues/264)
- [ ] [Keep find in page in step with what you type](https://github.com/crest-browser/Crest/issues/278)
- [ ] [Pointer reappears during playback and the sidebar opens on its own](https://github.com/crest-browser/Crest/issues/304)
- [ ] [Sidebar toggle and download animation don't follow a right-side sidebar or right-to-left layout](https://github.com/crest-browser/Crest/issues/329)
- [ ] [feature: Reorder Spaces in the drawer and rearrange the extension bar below the address bar](https://github.com/crest-browser/Crest/issues/339)
- [ ] [feature: Per-site developer mode toggle in the URL bar menu, persistent per origin](https://github.com/crest-browser/Crest/issues/351)
- [ ] [feature: Show extension actions next to the address field in Developer Mode](https://github.com/crest-browser/Crest/issues/352)
- [ ] [Hold-space cursor control doesn't work in the iPhone address bar](https://github.com/crest-browser/Crest/issues/370)
- [ ] [feature: Show a peek indicator on the originating tab when a Peek is open](https://github.com/crest-browser/Crest/issues/389)
- [ ] [feature: Let agents run several page steps in one call](https://github.com/crest-browser/Crest/issues/403)
- [ ] [feature: Connect an agent from Settings without a terminal](https://github.com/crest-browser/Crest/issues/404)
- [ ] [bug: Command palette treats custom URL schemes as web search queries instead of opening them](https://github.com/crest-browser/Crest/issues/408)
- [ ] [Tab switches Spaces instead of moving between form fields on iPad](https://github.com/crest-browser/Crest/issues/425)
- [ ] [bug: Preserve sidebar state and page state when moving a tab to another window/display](https://github.com/crest-browser/Crest/issues/477)
- [ ] [feature: Support multiple Private Browsing windows](https://github.com/crest-browser/Crest/issues/481)
- [ ] [feature: Share one extension install across chosen Spaces](https://github.com/crest-browser/Crest/issues/527)
- [ ] [Keep a Quick Window from another app clear of a new tab's keyboard on iPhone](https://github.com/crest-browser/Crest/issues/563)
- [ ] [Say so when a link from another app needs a locked Space](https://github.com/crest-browser/Crest/issues/564)

#### Completed

- [x] [Overhaul passwords and autofill: one-time codes, a new suggestion popup, and saved addresses and payment cards](https://github.com/crest-browser/Crest/issues/1344)

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

- [Image-conversion compatibility](https://github.com/crest-browser/Crest/issues/163) is delivered. Slack Huddles remain deferred and are not claimed fixed or validated.

- Extension work is active in the Chromium Mac product. Preserve per-Space isolation, keep extensions out of private windows, and report what Crest's host does not support instead of presenting partially initialized extension UI as working.
