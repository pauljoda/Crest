# Crest roadmap

This file summarizes public release outcomes and work that is still outstanding
or intentionally deferred. The live
[Crest Roadmap project](https://github.com/users/pauljoda/projects/3) shows
status; release milestones hold the actionable issue descriptions.

## Published releases

- [Crest 0.6.0](https://github.com/pauljoda/Crest/releases/tag/v0.6.0) — [release scope and completed work](https://github.com/pauljoda/Crest/milestone/2?closed=1).
- [Crest 0.5.7](https://github.com/pauljoda/Crest/releases/tag/v0.5.7) — [release scope and completed work](https://github.com/pauljoda/Crest/milestone/1?closed=1).

<!-- crest-roadmap-sync:start -->
## Active releases

Release milestones are shown from earliest to latest. The project board holds
the live status for each issue.

No release milestone is currently active.

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

- Extension work is active on macOS. Preserve per-Space isolation, prefer Safari Web Extension app bundles where native integration is required, and report WebKit compatibility limits instead of presenting partially initialized extension UI as working.
