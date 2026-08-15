---
title: iCloud Passwords in Crest
description: Understand the Apple-managed browser entitlement required before iCloud Passwords can pair and fill in Crest.
slug: /icloud-passwords
sidebar_label: iCloud Passwords
sidebar_position: 11
keywords: [iCloud Passwords, Password AutoFill, managed entitlement, Web Browser Public Key Credential Requests]
---

<span className="guide-validation-status">Apple capability requested · approval pending</span>

# iCloud Passwords in Crest

iCloud Passwords 3.3.0 verifies and installs from the Chrome Web Store, but **Password AutoFill does not work in the current Crest build**. Crest shows this limitation before installation, after installation, and in Extensions settings.

## Why the extension cannot pair yet

The WebExtension is only one half of iCloud Passwords. It connects to Apple's system password helper through native messaging. Apple protects that helper with a signed parent constraint: the browser must carry the managed **Web Browser Public Key Credential Requests** capability or use an explicitly approved browser identity.

The matching entitlement is:

```text
com.apple.developer.web-browser.public-key-credential
```

Crest has requested that capability, but the current app signature does not contain it. The iCloud action therefore reports that it cannot connect to its helper application. Changing the distribution method does not bypass Apple's approval.

## What Crest has validated

- [x] The signed Chrome Web Store package verifies and installs into one Space.
- [x] The review sheet warns that the current build cannot use Password AutoFill.
- [x] Exact-package compatibility shims let the service worker reach clean initial startup.
- [x] The action popup opens and reports the missing helper connection.
- [x] Apple's helper launch constraint was inspected and matched to the requested managed capability.
- [ ] Apple capability approval is pending.
- [ ] Pairing, unlock, save, and autofill must be retested with a newly provisioned signed build.

## What to do now

Use Crest's built-in Space-specific password manager, macOS Password AutoFill where WebKit offers it, or a password-manager extension that does not require a protected native companion. Installing iCloud Passwords repeatedly will not change the current signing entitlement.

After Apple approves the capability, Crest will need a new provisioning profile and signed build. This guide will be updated only after the full pairing and autofill workflow succeeds.

## Official reference

- [Web Browser Public Key Credential entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential)
