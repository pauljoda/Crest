---
title: Content blocking and site permissions
description: Control ads, trackers, camera, microphone, pop-ups, downloads, and external apps per Space.
slug: /content-blocking-and-site-permissions
keywords: [content blocking, ads, trackers, permissions, camera, microphone, pop-ups, downloads]
---

# Content blocking and site permissions

Privacy decisions belong to the current Space. A permission granted to a work account does not silently become a permission for the same host in Personal.

## Content blocking

Crest includes a small built-in ad and tracker ruleset that can be enabled or disabled per Space. It uses WebKit, so it is available on iPhone, iPad, and the WebKit build for Mac. Use the site controls or assign **Toggle Content Blocking** a shortcut when a site needs a quick exception.

The Chromium build for Mac has no built-in blocking. Install a content-blocking extension, such as uBlock Origin Lite, in each Space that needs it.

For broader filter-list coverage, install a content-blocking extension in the Space that needs it. Built-in protection and an extension can have different rule coverage, so check which layer is active before assuming the page itself is broken.

## Site permissions

Crest can remember decisions for:

- Camera
- Microphone
- Camera and microphone together
- Pop-ups
- Automatic downloads
- Opening external apps

Open Site Controls on the affected page to inspect or reset the decision. Settings also provides the Space-level view of stored permissions.

## Reset a site

If a site behaves as though an old choice still applies, first reset its saved permission rather than deleting the entire Space. Clearing all website data is broader: it can sign you out and remove local site state for that profile.

## Extension site access

Extension permissions are a separate layer. An extension may be installed but still blocked from the current host, or it may require approval for additional sites. See [Manage extension permissions and site access](../extensions/manage-permissions-site-access.md) for the extension-specific controls.
