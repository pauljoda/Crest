---
title: Set up 1Password in Crest
description: Understand the current production-signature gate for the verified 1Password Chrome extension in Crest for Mac.
slug: /onepassword
sidebar_label: 1Password setup
sidebar_position: 10
keywords: [1Password, native messaging, trusted browser, Add Browser, authorize Crest, Crest for Mac]
---

<span className="guide-validation-status">Measured path · Developer ID validation remains</span>

# Set up 1Password in Crest

The signed 1Password Chrome Web Store extension installs and starts in **Crest for Mac**. Crest validated the setup interface, normal sign-in navigation, persistent native messaging, BrowserSupport launch, and 1Password's additional-browser authorization UI. The tested Apple Development build was rejected by 1Password as `BrowserSignatureInvalid`, so unlock and autofill remain pending validation with the production release signature.

:::caution The official Mac release is required
Use the Developer ID signed and notarized Crest release installed as `/Applications/Crest.app`. A development build is not accepted by 1Password's browser-signature check. The Safari extension is not a substitute because its third-party Safari native handler is not portable to Crest.
:::

## Before you begin

- Install and unlock the current **1Password for Mac** app. Orion's comparable integration documents 1Password for Mac 8.10.16 or later as the browser-whitelisting baseline.
- Keep the production-signed Crest app in `/Applications`. An Apple Development signature is not sufficient.
- Choose the Crest Space and device that should own the extension. Installations and settings do not silently copy to another Space or device.

## Install the Chrome Web Store extension

1. In Crest for Mac, open the 1Password page in the Chrome Web Store.
2. Select **Add to Crest**.
3. Review the signed package, permissions, website access, compatibility notes, and destination Space in Crest's native sheet.
4. Select **Add Extension**, then **Done**.
5. Open **Crest Settings → Extensions** and confirm 1Password shows **Running** in that Space.
6. Open the 1Password action or welcome page. Selecting **Sign in** should open `my.1password.com` in a normal Crest tab.

## Authorize Crest in 1Password

1. Open and unlock **1Password for Mac**.
2. Select your account or collection at the top of the sidebar, then select **Settings**.
3. Select **Browser** in the sidebar.
4. Select **Add Browser**.
5. Choose the production-signed **Crest** app in `/Applications`.
6. Review 1Password's access prompt and select **Authorize**.

1Password warns that an additional browser receives access to saved information while 1Password is unlocked so it can save and fill logins. Only authorize the Crest build and developer you trust.

## What Crest validated

- [x] **Add to Crest** opened the native review and completed installation.
- [x] The extension appeared as **Running**.
- [x] The welcome and setup interface rendered.
- [x] **Sign in** opened a normal Crest tab at `my.1password.com`.
- [x] Unified logs showed `/Applications/1Password.app/Contents/MacOS/1Password-BrowserSupport` launch through Crest's native-messaging bridge.
- [x] Adding and authorizing Crest in 1Password displayed and completed the browser review UI.
- [x] The extension sent its account request and Crest carried the framed native message bidirectionally.
- [x] 1Password returned `BrowserVerificationFailed` with `BrowserSignatureInvalid` for the Apple Development build.
- [ ] Developer ID signed pairing, desktop unlock, and autofill remain to be completed.

Do not repeatedly reinstall the extension to fix `BrowserSignatureInvalid`; it is a Crest signing boundary, not a damaged 1Password installation. The next useful test uses the Developer ID signed and notarized Crest release.

## Official references

- [Connect additional browsers to the 1Password app](https://support.1password.com/additional-browsers/)
- [1Password browser code-signature requirements](https://support.1password.com/code-signature/)
- [1Password and Orion's comparable trusted-browser setup](https://help.kagi.com/orion/browser-extensions/1password.html)

If the extension does not show **Running**, the sign-in page does not open, or the desktop app does not connect after authorization, see [Troubleshoot partial compatibility](./troubleshoot-partial-compatibility.md).
