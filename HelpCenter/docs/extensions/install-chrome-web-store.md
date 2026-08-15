---
title: Install from the Chrome Web Store
description: Add a standards-based Chrome extension directly from its store page to the current Crest Space.
slug: /install-chrome-web-store
sidebar_label: Chrome Web Store
sidebar_position: 1
keywords: [Chrome Web Store, Add to Crest, CRX3, install extension, Space]
---

# Install from the Chrome Web Store

**Install most standards-based Chrome extensions** directly from their Chrome Web Store pages. Compatibility varies where an extension depends on Chrome-only APIs, a native companion, or an Apple-managed capability.

:::info Desktop today
The current extension installation and management interface is available in Crest for Mac.
:::

## Before you add it

Choose the Space and device that should own the extension. The package, enablement, permissions, storage, pinning, and website access remain independent from every other Space and device.

## Install the extension

1. In Crest on Mac, open the extension’s page in the **Chrome Web Store**.
2. Select **Add to Crest** beside the store’s button.
3. Wait while Crest downloads the signed CRX3 package and verifies its developer and Web Store signatures.
4. In Crest's native review sheet, confirm **Install In** shows the intended Space.
5. Open **Review Access and Compatibility**. Read the signed source, requested **Permissions**, **Website Access**, and any **Compatibility Warnings**.
6. Select **Add Extension**.
7. When Crest confirms the extension was added, select **Done**.

The extension is enabled only in the Space and device shown during review. To change it later, open **Crest Settings → Extensions** and choose that Space. Options pages, pinned actions, and keyboard commands remain attached to this local installation.

## Use it after installation

- Open **Site Controls** beside the address field to find the extension’s action. Pin the action if you want it in the active Space’s extension strip. See [Pin extensions and use popups](./pin-and-use-popups.md).
- Open **Crest Settings → Extensions**, choose the Space, and expand the extension to turn it on or off, open its options page, review status, or remove it.
- Review or change **Permissions** and **Website Access** independently for each Space. See [Manage permissions and website access](./manage-permissions-site-access.md).
- If the extension declares commands, assign them under **Crest Settings → Shortcuts**. See [Set extension keyboard shortcuts](./keyboard-shortcuts.md).

## Keep it updated

Chrome Web Store installations can use Crest’s extension updater. In **Crest Settings → Extensions**, turn on automatic updates, choose a frequency, or select **Check for Updates Now**. Crest updates only enabled Chrome Web Store installations and repeats the same signed-package and identity checks used during the original installation.

If Crest knows that a package has a limited workflow, the review sheet explains the impact before installation. Continuing produces an orange **added with limited compatibility** result, and the same plain-language explanation remains in Extensions settings. The package can still be installed when its supported features are useful.

:::caution Installation is not a universal compatibility promise
A package can verify, install, and start its worker while a later account, native-helper, or site workflow remains limited. Crest keeps known limits separate from unexpected **Needs attention** runtime failures.
:::

## When Add Extension is unavailable

Crest disables installation when the current build cannot supply a declared requirement safely. Crest for Mac offers `nativeMessaging` only to verified Chrome Web Store installations whose identity exactly matches a registered host's `allowed_origins`; unpacked extensions and Safari-app native handlers are not eligible. Read [Native companion limits](./native-companion-limits.md) instead of treating a different Safari app bundle as an automatic workaround.

Next: [Manage permissions and website access](./manage-permissions-site-access.md).
