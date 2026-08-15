---
title: Extension compatibility and known limitations
description: The measured startup boundary for current Chrome, Firefox, Safari, unpacked, native-companion, and popular extensions in Crest.
slug: /extension-compatibility
sidebar_label: Compatibility matrix
sidebar_position: 8
keywords: [extension compatibility, WebKit, Chrome extension, Firefox extension, Safari extension, partial compatibility, audit]
---

# Extension compatibility and known limitations

**Install most standards-based Chrome Web Store extensions, Firefox Add-ons, and Safari Web Extensions on Mac.** Compatibility varies where an extension depends on a browser-specific API, a native companion, or an Apple-managed capability.

:::info Desktop today
Extension installation, actions, options, shortcuts, and management are currently available in Crest for Mac. Installations and settings remain per Space and per device.
:::

Crest measures package verification, installation, and runtime startup separately from complete workflow support. A package can load cleanly while an optional feature still needs an API WebKit does not implement.

## What Crest supports

- A native permission and compatibility review for signed CRX3 packages from the Chrome Web Store, and for Mozilla-signed add-ons from Firefox Add-ons.
- Per-Space and per-device installation, storage, enablement, permissions, website access, and pinning.
- WebExtension action popups, options pages, and keyboard commands where their APIs are available in WebKit.
- Plain-language **Running**, **Limited compatibility**, **Needs attention**, **Off**, and blocked states, with JavaScript errors collapsed under **Technical Details**.
- Known package-specific limits in the pre-install review, the orange post-install result, and the persistent Settings row.
- **Load Unpacked…** for development and manual testing, without native-messaging access.
- Discovery of ordinary WebExtension resources inside signed Safari apps, without treating Safari native handlers as portable.
- Automatic signed updates for enabled Chrome Web Store installations. Firefox Add-ons can be refreshed from their listing and are verified again before replacement.

See [Direct build, App Store, and native companions](./native-companion-limits.md) for the distribution boundary.

## Signed-package audit

Validated on August 10, 2026:

<table className="guide-responsive-table guide-compatibility-table">
  <thead>
    <tr><th>Extension</th><th>Version</th><th>Startup result</th><th>Measured boundary</th></tr>
  </thead>
  <tbody>
    <tr><td data-label="Extension">Dark Reader</td><td data-label="Version">4.9.129</td><td data-label="Startup result">Loads cleanly</td><td data-label="Measured boundary">No startup error observed.</td></tr>
    <tr><td data-label="Extension">uBlock Origin Lite</td><td data-label="Version">2026.804.1652</td><td data-label="Startup result">Loads cleanly</td><td data-label="Measured boundary">Declarative Net Request package loaded without a startup error.</td></tr>
    <tr><td data-label="Extension">1Password</td><td data-label="Version">8.12.30.21</td><td data-label="Startup result">Production-signature gated</td><td data-label="Measured boundary">Setup, sign-in navigation, BrowserSupport launch, persistent messaging, and browser authorization were verified. The Apple Development build was rejected as <code>BrowserSignatureInvalid</code>; Developer ID pairing and autofill remain.</td></tr>
    <tr><td data-label="Extension">SponsorBlock</td><td data-label="Version">6.1.6</td><td data-label="Startup result">Loads cleanly</td><td data-label="Measured boundary">No manifest or startup runtime error observed.</td></tr>
    <tr><td data-label="Extension">Bitwarden</td><td data-label="Version">2026.7.0</td><td data-label="Startup result">Partial / experimental</td><td data-label="Measured boundary">The package and core worker load. Notification-click handling is unsupported; account unlock and autofill are not yet certified.</td></tr>
    <tr><td data-label="Extension">Grammarly</td><td data-label="Version">14.1319.0</td><td data-label="Startup result">Partial / experimental</td><td data-label="Measured boundary">Managed storage, cookie, and telemetry limits are reported.</td></tr>
    <tr><td data-label="Extension">React Developer Tools</td><td data-label="Version">7.0.1</td><td data-label="Startup result">Partial / experimental</td><td data-label="Measured boundary">Isolated execution world is unsupported.</td></tr>
    <tr><td data-label="Extension">Tampermonkey</td><td data-label="Version">5.5.0</td><td data-label="Startup result">Partial / experimental</td><td data-label="Measured boundary">WebKit rejects <code>tabs.onUpdated</code> startup registration.</td></tr>
    <tr><td data-label="Extension">iCloud Passwords</td><td data-label="Version">3.3.0</td><td data-label="Startup result">Apple entitlement pending</td><td data-label="Measured boundary">The worker loads with exact-package compatibility shims, but Apple's password helper rejects browsers without its managed Web Browser Public Key Credential entitlement. Pairing and autofill are blocked in the current build.</td></tr>
  </tbody>
</table>

“Loads cleanly” covers verification, installation, WebKit context load, and initial background startup. It does not certify every site, account, popup, update, native-companion authorization, or optional feature.

## Firefox add-on audit

Validated on August 13, 2026. Crest verifies each add-on against the checksum, size, and identity Mozilla published for that exact version before installing it.

<table className="guide-responsive-table guide-compatibility-table">
  <thead>
    <tr><th>Extension</th><th>Version</th><th>Startup result</th><th>Measured boundary</th></tr>
  </thead>
  <tbody>
    <tr><td data-label="Extension">Dark Reader</td><td data-label="Version">4.9.129</td><td data-label="Startup result">Loads cleanly</td><td data-label="Measured boundary">No manifest or runtime error observed, and no unsupported API reported.</td></tr>
    <tr><td data-label="Extension">uBlock Origin</td><td data-label="Version">1.73.0</td><td data-label="Startup result">Partial / experimental</td><td data-label="Measured boundary">One <code>commands</code> manifest entry is rejected and the background script stops early. Its request-blocking model is not implemented by WebKit; uBlock Origin Lite from the Chrome Web Store is the working alternative.</td></tr>
    <tr><td data-label="Extension">Bitwarden</td><td data-label="Version">2026.7.0</td><td data-label="Startup result">Partial / experimental</td><td data-label="Measured boundary">The package and core worker load. Notification-click handling is unsupported. The Firefox build does not request a native companion, so it is not blocked before installation.</td></tr>
  </tbody>
</table>

Sidebars, container tabs, extension themes, and blocking <code>webRequest</code> are expected gaps for every Firefox add-on. See [Install from Firefox Add-ons](./install-firefox-add-ons.md).

## 1Password's measured boundary

The Chrome Web Store package installed as **Running**, rendered its setup interface, opened `my.1password.com` in a normal Crest tab, and caused Crest for Mac to launch `/Applications/1Password.app/Contents/MacOS/1Password-BrowserSupport`.

Crest completed 1Password's additional-browser authorization UI and traced the extension's first account request. The helper rejected the Apple Development signature as <code>BrowserSignatureInvalid</code>. The Developer ID signed and notarized Crest release is required for the next pairing and autofill test. Follow [Set up 1Password in Crest](./onepassword.md).

## iCloud Passwords' measured boundary

iCloud Passwords installs and its worker starts after exact-package WebKit compatibility shims. Its native helper is separately protected by Apple: the current Crest signature does not carry the managed browser credential entitlement, so the popup cannot pair and Password AutoFill does not work. Crest has requested the capability. See [iCloud Passwords in Crest](./icloud-passwords.md).

## Safari-only formats

Safari content blockers and legacy Safari App Extensions are not WebExtensions and are not supported.

### wBlock

wBlock is a hybrid. Its toolbar and userscript portion use Safari Web Extensions, but its primary blocker uses five Safari-only content-blocker extensions. Crest cannot reproduce the core wBlock blocking behavior and does not market wBlock as fully supported.

If an installed extension reports an error or a feature does not respond, continue with [Troubleshoot partial compatibility](./troubleshoot-partial-compatibility.md).
