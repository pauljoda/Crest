---
title: Native companions and verified identities
description: Understand which extensions Crest for Mac can connect to and why unpacked and Safari-native handlers stay blocked.
slug: /native-companion-limits
sidebar_label: Native companion limits
sidebar_position: 8
keywords: [Crest for Mac, nativeMessaging, native companion, verified identity, unpacked extension]
---

# Native companions and verified identities

Most WebExtensions do not need a desktop helper. Those extensions use the WebExtension APIs implemented by WebKit. A smaller group—password managers are the common example—uses `nativeMessaging` to connect the extension to a separate Mac app.

## What can connect

<table className="guide-responsive-table guide-build-table">
  <thead>
    <tr><th>Package</th><th>Ordinary WebExtensions</th><th>Native companion helpers</th></tr>
  </thead>
  <tbody>
    <tr><td data-label="Package"><strong>Verified Chrome Web Store extension</strong></td><td data-label="Ordinary WebExtensions">Supported where WebKit implements the required APIs.</td><td data-label="Native companion helpers">Available only when the exact verified extension identity appears in the native host's <code>allowed_origins</code>.</td></tr>
    <tr><td data-label="Package"><strong>Firefox, unpacked, or Safari package</strong></td><td data-label="Ordinary WebExtensions">Supported where WebKit implements the required APIs.</td><td data-label="Native companion helpers">Unavailable because Crest cannot establish the required Chrome Web Store identity.</td></tr>
  </tbody>
</table>

Crest explains this identity boundary before installation instead of allowing an extension to appear functional while its companion connection silently fails.

## Why unpacked extensions cannot use native messaging

**Load Unpacked…** is useful for development and manual testing, but an unpacked package has no verified Chrome Web Store identity. Crest therefore never grants it native-messaging access.

## Why a Safari app bundle is not enough

**Scan for Apps** and **Choose App…** can discover ordinary Safari Web Extension resources. The app's Safari-native handler, Safari App Extension behavior, and content blockers are not portable to another browser.

When a developer offers a standards-based WebExtension or Chrome Web Store version, use that package in Crest. Loading a Safari extension's UI is not evidence that its desktop-app bridge works.

## What Crest validates

Before launching a native host, Crest checks the signed Chrome Web Store identity, resolves a registered host manifest, requires an exact `allowed_origins` match, and speaks Chrome's little-endian framed JSON protocol. Both one-shot `sendNativeMessage` calls and persistent `connectNative` ports are supported.

## Apple-protected helpers are a separate gate

iCloud Passwords uses Apple's system password helper rather than a normal registered Chrome host. Apple signs that helper with a parent launch constraint: a browser must carry the managed `com.apple.developer.web-browser.public-key-credential` entitlement or have an explicitly approved signing identity.

Crest has requested **Web Browser Public Key Credential Requests**, but the current build is not signed with it. iCloud Passwords therefore shows **Limited compatibility** and Password AutoFill remains unavailable. The distribution method cannot bypass this constraint. After Apple approves the capability, Crest must be reprovisioned and the complete pairing and autofill workflow retested.

## Availability

Official Crest for Mac builds are distributed through GitHub Releases. The release workflow Developer ID signs and notarizes the app, validates it with Gatekeeper, and publishes updates through a signed Sparkle appcast. Development-signed builds are not equivalent to an official release for companion apps that verify the browser signature.

For measured companion workflows, continue with [Set up 1Password in Crest](./onepassword.md) or [iCloud Passwords in Crest](./icloud-passwords.md).
