---
title: Troubleshoot partial extension compatibility
description: Diagnose a Chrome or Firefox extension that installs but reports Needs attention or has a feature limited by WebKit.
slug: /troubleshoot-extension-compatibility
sidebar_label: Troubleshoot partial support
sidebar_position: 9
keywords: [partial extension support, experimental, Needs attention, Technical Details, WebKit limitation]
---

# Troubleshoot partial extension compatibility

An extension can verify, install, and start while one optional feature reaches a browser-specific API. Crest reports what it can observe without treating one error as proof that every extension feature failed.

## Read the status first

- **Running** means the enabled WebKit context loaded without an observed runtime error. It does not certify every workflow.
- **Limited compatibility** means a known package-specific workflow is unavailable even though the extension installed or started.
- **Needs attention** means the context failed to load or reported a runtime problem. Expand the row for Crest's plain-language explanation.
- **Blocked** means Crest identified an unsafe or unavailable requirement before installation.
- **Off** keeps the installation and Space-local configuration but does not run it.

## Try the smallest recovery

1. Open **Crest Settings → Extensions**.
2. Choose the Space and device where the problem occurs.
3. Expand the extension and read the status explanation.
4. Turn the extension off and back on.
5. Update or reinstall the store-sourced package. Chrome Web Store installations can use **Check for Updates Now**; for a Firefox extension, reopen its Firefox Add-ons listing and install the current version into the same Space.
6. Review **Permissions** and **Website Access** for a blocked rule.
7. Open the extension's **Options** page when it provides one and review feature-specific settings.

Reinstalling does not fix an app-signature or managed-entitlement gate. `BrowserSignatureInvalid` needs a production-signed Crest build; iCloud Passwords needs Apple browser approval and a newly provisioned build.

## Read Technical Details without overgeneralizing

Open **Technical Details** to see the JavaScript errors and unsupported APIs reported by WebKit. Include those details, the extension version, Crest build, Space, device, and failing workflow in a bug report.

Common measured limitations include notification-click events, managed storage, isolated scripting execution worlds, and `tabs.onUpdated` registration. Another feature in the same extension may still work.

## Check the native-companion boundary

If the extension needs a desktop app, confirm you are using the official Crest for Mac release and a verified Chrome Web Store package. Development-signed builds may be rejected by a companion's signature policy, unpacked extensions are ineligible, and a Safari app's native handler is not portable.

See [Native companions and verified identities](./native-companion-limits.md) and the [current compatibility matrix](./compatibility.md).
