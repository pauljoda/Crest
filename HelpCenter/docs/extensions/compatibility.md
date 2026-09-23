---
title: Extension known limitations
description: Where extensions run in Crest, and the limits that apply to them.
slug: /extension-compatibility
sidebar_label: Known limitations
sidebar_position: 8
keywords: [extension compatibility, known limitations, Chrome extension, Chromium, private windows]
---

# Extension known limitations

Crest for Mac runs Chrome extensions from the Chrome Web Store on its Chromium engine. The [extension compatibility](./api-compatibility-matrix.md) page lists which browser features Crest connects to its interface. This page collects the limits.

:::info Mac, Chromium build
Extensions run only in the Chromium build of Crest for Mac. The WebKit build for Mac, and Crest on iPhone and iPad, run no extensions. Installations and settings stay in one Space on one device.
:::

## Package formats

- Chrome Web Store extensions install and update through Chromium.
- Unpacked extensions install from Chromium's extension manager in developer mode.
- Firefox add-ons, Safari Web Extensions, Safari content blockers and Safari App Extensions are not supported.

## Spaces and private windows

- Each Space has its own installation and data. Copying an extension to another Space installs it fresh; its data does not follow.
- Private windows run only the extensions allowed there, and you cannot install or remove extensions from a private window.
- A locked Space cannot receive an extension until you unlock it.

## Browser features

- Crest does not yet match Chrome for every extension API. A feature that needs part of Chrome's window that Crest does not draw may be missing.
- A window an extension opens appears as a Crest window in the extension's Space. A requested window state, such as maximized, is ignored.
- Extension shortcuts work only when Crest's own shortcuts don't use the same keys.

## Companion apps

Extensions that talk to a Mac app, such as password managers, depend on that app trusting Crest's signature. See [Native companions](./native-companion-limits.md), [Set up 1Password in Crest](./onepassword.md) and [iCloud Passwords in Crest](./icloud-passwords.md).

## Extensions from older Crest versions

Earlier WebKit-based versions of Crest ran extensions through their own compatibility layer. Those installations do not carry over to the Chromium build. Install each extension again from the Chrome Web Store in the Space you want.

If an installed extension misbehaves, continue with [Troubleshoot an extension](./troubleshoot-partial-compatibility.md).
