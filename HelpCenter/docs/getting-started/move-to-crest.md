---
title: Move your browser data to Crest
description: Review imports from Arc and the other browsers on your Mac, and export portable Crest data.
slug: /move-to-crest
keywords: [import, migrate, Arc, profiles, bookmarks, extensions, passwords, export]
---

# Move your browser data to Crest

Browser-to-browser import runs on Mac. Crest prepares a visual review first so you can decide what arrives and where it belongs before the live session changes.

## Import during setup

Choose a detected browser, then review each source Space, profile, or window. Depending on what that browser exposes, Crest can bring across Spaces or profiles, tabs, bookmarks, saved folders, split views, tab groups, colors, icons, extensions, and supported passwords.

| Source | Crest can review |
| --- | --- |
| Arc | Spaces (each profile's as one Sub-Space group), tabs, folders, split views, colors, icons, extensions, and supported passwords |
| Browsers built on Chromium | Profiles, bookmarks, open tabs, tab groups, split views, extensions, and supported passwords (not from a browser found by **Scan for more**) |
| Other browsers | Windows, open tabs, and pinned tabs, plus bookmarks, profiles, workspaces (each profile's as one Sub-Space group), folders, split views, tab groups, icons, and colors where Crest can read them |

If your browser isn't listed, choose **Scan for more** and Crest looks for other browsers built on Chromium. Not every browser can be found this way; you can [request support for one](https://github.com/crest-browser/Crest/issues/new?template=feature_request.yml&title=Import%20from%20).

In the review, each Space shows the Chrome Web Store extensions it brings under its address bar. Turn off any you don't want, and Crest installs the rest once the import finishes, without asking about each one.

For every source group, you can remove individual items, choose a new or existing Crest Space, and customize that destination before importing. Spaces or workspaces that share one profile arrive as one [Sub-Space](../spaces/sub-spaces.md) group, so they keep sharing sign-ins; the review outlines each group and can bring a Space in on its own. If one Space of a group goes into a Space you already have, the rest of the group become Sub-Spaces of that Space's group. Imported passwords are saved once for each group. When an import holds more than Crest keeps, it brings what fits and lists what it left out.

## Import later

Open **Settings → Advanced**. The **Import & Export** section can import a Crest archive, bookmark HTML, browser history, or open tabs from supported sources. **Import from Another Browser…** opens the same review over your current Spaces, where a Space goes into the Space you already have with the same name unless you choose another destination.

## Export a portable backup

Choose **Export Browser Data…** in **Settings → Advanced**. A Crest archive includes Spaces, folders, saved and current tabs, Archive, history, and browsing preferences.

For safety, the portable archive does not contain passwords, cookies, website storage, site permissions, downloaded files, favicons, or extensions. Password export is a separate, device-authenticated plaintext operation: select a Space in the Settings sidebar, then choose **Passwords → Export Passwords…**. Treat that file as sensitive.

## After import

Browse each new Space once before removing data from your old browser. Check signed-in state, saved locations, folder nesting, and any critical extension workflow. If iCloud sync is enabled, imported Spaces and tabs can then follow you to iPad and iPhone.

