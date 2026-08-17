---
title: Localhost and developer tools
description: Use Crest’s automatic developer toolbar, capture tools, console, network panel, and Web Inspector on Mac.
slug: /localhost-developer-tools
keywords: [localhost, developer mode, Web Inspector, console, network, capture]
---

# Localhost and developer tools

On Mac, Crest automatically shows its developer toolbar for local development addresses. This includes `localhost`, loopback and private-network addresses, single-label hosts, common local suffixes such as `.local` and `.test`, and file URLs.

## Toolbar controls

- Edit the complete development URL without losing the visible route.
- Copy the current link.
- Open Site Settings and inspect permissions.
- Use **Capture in Portrait Mode**, **Copy Full Page Capture**, or drag a region to copy it.
- Toggle the Web Inspector Console, Network panel, or element inspection.

The toolbar leaves when the focused page is no longer a local-development address, keeping ordinary browsing chrome quiet.

## Open Web Inspector directly

Use **Option-Command-I**, the menu, or the command palette. Web Inspector follows the focused page, including the focused card inside Split View.

## Security boundary

Developer tools make page internals visible and can change runtime state. Use them only for sites and code you trust. A certificate warning, external-app request, or protected permission remains subject to Crest’s normal navigation and site-permission policies; localhost mode does not bypass those checks.
