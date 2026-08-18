# Crest roadmap

This file summarizes public release outcomes and work that is still outstanding
or intentionally deferred. The live
[Crest 0.5 project](https://github.com/users/pauljoda/projects/3) shows status;
the matching [0.5 milestone](https://github.com/pauljoda/Crest/milestone/1)
holds the actionable issue descriptions.

## Crest 0.5

- [Global sidebar widgets](https://github.com/pauljoda/Crest/issues/4) for
  update availability and active media sessions.
- [Website notifications](https://github.com/pauljoda/Crest/issues/5) with
  explicit per-site and per-Space controls.
- [Picture-in-picture](https://github.com/pauljoda/Crest/issues/6), including an
  optional automatic mode when leaving a playing video tab.
- [An About section](https://github.com/pauljoda/Crest/issues/7) for build,
  update, license, and community information.
- [An adaptive full mobile sidebar](https://github.com/pauljoda/Crest/issues/8)
  for iPad, multitasking, and wider iPhone layouts.
- [Native emoji picking](https://github.com/pauljoda/Crest/issues/9) for icon
  customization across Apple platforms.

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
