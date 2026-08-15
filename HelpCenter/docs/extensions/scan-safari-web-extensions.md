---
title: Scan Mac apps for Safari Web Extensions
description: Find signed Safari Web Extension components inside apps installed on your Mac and add an eligible component to one Space.
slug: /scan-safari-web-extensions
sidebar_label: Scan Mac apps
sidebar_position: 3
keywords: [Scan for Apps, Choose App, Safari Web Extension, macOS, signed app]
---

# Scan Mac apps for Safari Web Extensions

Crest can discover ordinary Safari Web Extension resources in signed apps on your Mac. Discovery does not make a third-party native companion, Safari App Extension, or content blocker portable to Crest.

## Scan installed applications

1. Open **Crest Settings → Extensions**.
2. Under **Space**, choose the Space that should own the extension.
3. In **Find Extensions**, select **Scan for Apps**.
4. Wait for **Scanning Applications…** to finish.
5. For a result you recognize, open **Review Access and Compatibility**.
6. Confirm the **Signed Developer**, **Install In** Space, permissions, website access, and compatibility warnings.
7. Select **Add**.

The host app and other Spaces are unchanged. Removing the extension from Crest removes that Space’s extension data, not the Mac app.

## Choose one app directly

If scanning does not show the app, select **Choose App…**, choose its signed `.app` bundle, and review the discovered WebExtension in the same way.

## What Crest will not offer

- Safari content blockers are not WebExtensions.
- Legacy Safari App Extensions are not WebExtensions.
- Loading a Safari Web Extension’s UI does not prove that its app-specific native connection works.

:::warning Native companion boundary
Scanning a Safari app never grants its third-party native handler to Crest. Crest limits its separate Chrome-style bridge to verified Chrome Web Store installations whose registered host explicitly allows that verified identity.
:::

For manual development packages, use **Load Unpacked…**. Treat that as a developer path rather than a substitute for a signed production package.
