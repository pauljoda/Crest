---
title: Understand extension status and Technical Details
description: Read Running, Limited compatibility, Needs attention, Off, and blocked installation states without mistaking installation for full compatibility.
slug: /extension-status
sidebar_label: Status & Technical Details
sidebar_position: 7
keywords: [Running, Limited compatibility, Needs attention, Blocked, Technical Details, extension error, troubleshooting]
---

# Understand extension status and Technical Details

Crest treats compatibility as an observed runtime result, not a promise based only on a manifest.

## Before and immediately after installation

Known package-specific limits appear in **Review Access and Compatibility** before installation. If you continue, Crest replaces the ordinary green completion treatment with an orange **added with limited compatibility** result. The explanation then remains attached to the extension in Settings.

## Running

**Running** means the extension is enabled, its WebKit context loaded, and Crest has not observed a startup runtime error. It does not certify every website, account flow, native-companion authorization, optional feature, or future extension update.

## Limited compatibility

**Limited compatibility** means Crest knows that a specific workflow is unavailable even though the package installed or its worker started. Read the plain-language impact before deciding whether the remaining features are useful.

For example, iCloud Passwords currently says **Apple browser approval is needed**. Its worker starts, but pairing and Password AutoFill remain unavailable. The raw WebKit and JavaScript details stay collapsed under **Technical Details**.

## Needs attention

**Needs attention** means an enabled extension did not load or reported a runtime failure. Expand its row in **Crest Settings → Extensions** to see a plain-language explanation.

Try these smallest steps first:

1. Turn the extension off and back on.
2. Update or reinstall the extension.
3. Check whether the failing feature depends on an API listed under **Unsupported APIs**.

## Blocked

A blocking compatibility message appears during installation when Crest can identify a requirement it cannot satisfy safely. **Add Extension** remains unavailable, and Crest explains the boundary before creating a misleading installation.

Crest for Mac blocks native-companion access for unpacked extensions, unknown store identities, and native-host manifests that do not explicitly allow the verified Chrome Web Store extension ID.

## Off

**Off** means the extension remains installed in the Space but is disabled. Its stored configuration remains available for the next time you enable it.

## Technical Details

When an installed extension reports a runtime problem, the user-facing impact appears first. Open **Technical Details** to see the JavaScript errors reported by the extension and WebKit.

Technical Details are intended for troubleshooting and bug reports. They can identify the failing API or script, but an error string alone does not prove that every other extension feature failed.

Continue with [Troubleshoot partial extension compatibility](./troubleshoot-partial-compatibility.md) for a measured recovery sequence and the current named WebKit limitations.
