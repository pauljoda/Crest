---
title: Extension compatibility
description: Which extensions Crest runs, where, and which Chrome extension features Crest connects to its own interface.
slug: /extension-api-compatibility
sidebar_label: Extension compatibility
sidebar_position: 8
keywords: [extension compatibility, Chrome extension, Chromium, side panel, extension shortcuts, iCloud Passwords]
---

# Extension compatibility

Extensions in Crest for Mac run on the Chromium engine. Chromium runs each extension itself, with its own background service worker, APIs and permission checks, so an extension behaves much as it does in Chrome. Crest connects the parts that appear in a browser window, such as the toolbar, popups, side panels and shortcuts, to its own interface.

## Where extensions run

| Crest build | Extensions |
| --- | --- |
| Crest for Mac, Chromium engine | Chrome extensions from the Chrome Web Store |
| Crest for Mac, WebKit engine | None |
| Crest on iPhone and iPad | None |

Crest does not install Firefox add-ons or Safari Web Extensions. Many of them also publish a Chrome version. See [Firefox add-ons](./install-firefox-add-ons.md) and [Safari Web Extensions](./scan-safari-web-extensions.md).

## Packages

| Package | Support |
| --- | --- |
| Chrome Web Store extensions | Supported. Chromium checks the publisher's signature and the extension's ID before Crest shows its install review. |
| Extensions in more than one Space | Each Space gets its own installation and data. A copy reuses your approval only when the extension's identity, version and permission warnings match what you reviewed. |
| Unpacked extensions | For development. Install them from Chromium's extension manager in developer mode, which Crest's Extensions settings link to. |
| Firefox `.xpi` packages | Not supported. |
| Safari Web Extensions, Safari content blockers, Safari App Extensions | Not supported. |

## Browser features extensions use

| Feature | In Crest |
| --- | --- |
| Toolbar actions and popups | The action appears in the Space's extension strip or in Site Controls. Its popup opens below the button in a window attached to the Crest window. Pinned actions belong to the Space, so they appear even on the Start Page. |
| Side panels | `chrome.sidePanel` opens as a card beside the page it belongs to. The action's context menu, an icon click set to open the panel, and `sidePanel.open()` and `close()` all reach that card. |
| Keyboard shortcuts | `chrome.commands` shortcuts work when Crest's own shortcuts do not use the same keys. Change them on Chromium's extension shortcuts page, linked from Crest's Extensions settings. See [Set extension keyboard shortcuts](./keyboard-shortcuts.md). |
| New windows | `chrome.windows.create` opens a Crest window in the Space that owns the extension's profile. A requested window state is ignored. A request no Space can host fails with an error. |
| Private windows | Only extensions you allow in private windows run there. |
| Tab sharing and debugging bars | Chromium's confirmation bars, such as the one `chrome.debugger` shows, appear inside the page. |
| Updates | Chromium updates Chrome Web Store extensions and checks their signatures and permissions. |
| Native companion apps | Supported through `nativeMessaging`. When a companion app registered its helper only for Google Chrome, Crest also looks in Chrome's locations. A helper still answers only the extensions it lists. See [Native companions](./native-companion-limits.md). |

## Known limits

- Crest's registration of the Chromium engine states that full extension API parity is not complete. Features that need a Chrome browser window Crest does not draw may be missing.
- Apple's iCloud Passwords helper checks the browser's signature and entitlements before it pairs. See [iCloud Passwords in Crest](./icloud-passwords.md).
- An extension that is still enabled but whose files are gone shows no toolbar tile or settings row, and its action reports that it is unavailable.

For package-specific native limits, continue with [Direct build, App Store, and native companions](./native-companion-limits.md).
