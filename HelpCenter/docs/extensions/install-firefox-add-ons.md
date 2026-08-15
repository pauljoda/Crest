---
title: Install from Firefox Add-ons
description: Add a Firefox extension directly from its addons.mozilla.org page to the current Crest Space.
slug: /install-firefox-add-ons
sidebar_label: Firefox Add-ons
sidebar_position: 2
keywords: [Firefox Add-ons, addons.mozilla.org, AMO, Add to Crest, XPI, install extension, Space]
---

# Install from Firefox Add-ons

**Install most Firefox extensions** directly from their **addons.mozilla.org** pages. Compatibility varies where an extension depends on a Firefox-only API or a native companion.

:::info Desktop today
The current extension installation and management interface is available in Crest for Mac.
:::

Firefox extensions are often a close fit for Crest. Crest's engine runs the promise-based `browser.*` APIs Firefox extensions are written against, and it supports Manifest V2 extensions with a persistent background page.

## Before you add it

Choose the Space and device that should own the extension. The package, enablement, permissions, storage, pinning, and website access remain independent from every other Space and device.

## Install the extension

1. In Crest on Mac, open the extension's page on **addons.mozilla.org**.
2. Select **Add to Crest**, below the page's own install button.
3. Wait while Crest downloads the add-on from Mozilla and checks it against the checksum, size, and identity Firefox Add-ons published for it.
4. In Crest's native review sheet, confirm **Install In** shows the intended Space.
5. Open **Review Access and Compatibility**. Read the requested **Permissions**, **Website Access**, and any **WebKit Compatibility Warnings**.
6. Select **Add Extension**.
7. When Crest confirms the extension was added, select **Done**.

The extension is enabled only in the Space and device shown during review. To change it later, open **Crest Settings → Extensions** and choose that Space.

## Use it after installation

- Open **Site Controls** beside the address field to find the extension’s action. Pin the action if you want it in the active Space’s extension strip. See [Pin extensions and use popups](./pin-and-use-popups.md).
- Open **Crest Settings → Extensions**, choose the Space, and expand the extension to turn it on or off, open its options page, review status, or remove it.
- Review or change **Permissions** and **Website Access** independently for each Space. See [Manage permissions and website access](./manage-permissions-site-access.md).
- If the extension declares commands, assign them under **Crest Settings → Shortcuts**. See [Set extension keyboard shortcuts](./keyboard-shortcuts.md).

## Get a newer version

Crest’s automatic updater currently covers Chrome Web Store installations. To refresh a Firefox extension, reopen its Firefox Add-ons listing in Crest, select **Add to Crest**, review the current version, and install it into the same Space. Crest verifies the new package against Mozilla’s listing before replacing the installation.

## What Crest checks before installing

Crest resolves the listing through Mozilla's public add-ons API and then refuses anything that does not match it exactly:

- The download must come from `addons.mozilla.org` over HTTPS, and must still be on that host after any redirect.
- The downloaded file must reproduce the **SHA-256 checksum** and **byte count** Mozilla published for that exact version.
- The archive must carry **Mozilla's signature files**. A hand-built or side-loaded `.xpi` is refused.
- If the add-on declares its own Firefox add-on ID, it must match the ID on the listing.

Only listings for **extensions** are eligible. Themes, dictionaries, and language packs are not WebExtensions Crest can host, so **Add to Crest** does not appear on their pages.

## What is not supported

Some Firefox capabilities have no equivalent in Crest's engine. An extension that depends on one of them still installs, but that feature will not work:

- **Sidebars** (`sidebar_action`)
- **Container tabs** (`contextualIdentities`)
- **Browser themes** applied by an extension
- **Request blocking and rewriting** through blocking `webRequest`, which is how some older content blockers work

Crest lists what it detected under **WebKit Compatibility Warnings** in the review sheet before you install, and keeps the same explanation in Extensions settings afterward.

:::caution Installation is not a universal compatibility promise
A package can verify, install, and start its background script while a later account, helper, or site workflow remains limited. Crest keeps known limits separate from unexpected **Needs attention** runtime failures.
:::

## Native companion apps are not available

Crest verifies native companion access for Chrome Web Store extensions only, because that path can match an extension's verified store identity against a registered host's permitted origins. A Firefox add-on that requests `nativeMessaging` cannot be installed; Crest explains this before installation. If the extension also ships a Chrome Web Store version, install that version in Crest for Mac instead. See [Native companion limits](./native-companion-limits.md).

Next: [Manage permissions and website access](./manage-permissions-site-access.md).
