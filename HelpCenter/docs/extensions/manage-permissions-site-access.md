---
title: Manage permissions and website access per Space
description: Review and change an extension’s permissions and site rules without changing another Crest Space.
slug: /manage-extension-permissions
sidebar_label: Permissions & site access
sidebar_position: 4
keywords: [extension permissions, Website Access, Ask, Allow, Block, Space isolation]
---

# Manage permissions and website access per Space

Every Space and device keeps its own extension permissions and website access. Allowing a tool in Work on one Mac does not silently grant it the same access in Personal or another device.

## Change an access decision

1. Open **Crest Settings → Extensions**.
2. Under **Space**, choose **Manage extensions for** and select the Space you want to change.
3. Expand the extension’s row.
4. Under **Permissions** or **Website Access**, open the menu beside an entry.
5. Choose **Ask**, **Allow**, or **Block**.

| Choice | What it means |
| --- | --- |
| **Ask** | Crest can request a decision when the extension needs that access. |
| **Allow** | Grant that permission or website rule in this Space. |
| **Block** | Deny that permission or website rule in this Space. |

Changes apply to this installation in this Space and device. The same extension installed elsewhere keeps its own decisions and storage.

## Review status beside access

The same expanded row shows whether the extension is **Running**, **Needs attention**, or **Off**. Read the plain-language status before changing permissions; a WebKit API limitation is different from a website-access rule. Open **Technical Details** only when you need the reported JavaScript error for troubleshooting.

## Turn an extension off without removing it

Use the **Enabled** switch on the extension row. Turning it off preserves the installation and its Space-local configuration. Turn it back on when you need it again.

## Remove it and its Space-local data

Expand the row and select **Remove Extension**. Confirm **Remove from _Space_**. Crest removes the extension and its data from that Space; the host app and other Spaces are unchanged.

Private Spaces must be unlocked before Crest reveals or changes their installed extensions.
