---
title: Share sign-ins across Spaces with Sub-Spaces
description: Group Spaces so they share one set of sign-ins, history, passwords and extensions, while each keeps its own tabs and look.
slug: /sub-spaces
keywords: [Sub-Spaces, groups, shared profile, shared sign-ins, cookies, Separate Pinned Tabs, primary, Arc profiles, Zen workspaces]
---

import GuideScreenshot from '@site/src/components/GuideScreenshot';

# Share sign-ins across Spaces with Sub-Spaces

Every Space starts with sign-ins of its own. A Sub-Space shares another Space's instead: it browses with that Space's session while keeping its own tabs, folders and look. Use Sub-Spaces when several Spaces should be signed in to the same accounts, such as a Space for each client on one work account, or a Space for each class on one school account.

A Space and its Sub-Spaces form a group. The Space that leads it is the group's primary.

<GuideScreenshot
  src="/img/guides/sub-spaces/settings-group.png"
  alt="Crest Settings with Client A and Client B indented under Work in the sidebar, and Work's page showing the crests of Work, Client A and Client B"
  caption="Sub-Spaces sit under their primary in Settings, and a group's page shows the crests of its Spaces."
/>

## What a group shares

Every Space of a group uses the same:

- Sign-ins, cookies, caches and other website data
- History
- Crest Passwords
- Extensions on Mac
- Site permissions and content-blocking choices
- Lock, and whether coding agents may use it

Each Space keeps its own:

- Current, saved and archived tabs, folders and Split View groups
- Name, crest, colors and sidebar
- Browsing settings, such as its search engine and download folder

Settings that a group shares say so at the end of their page, for example "Shared by Work's Sub-Spaces."

## Pinned tabs

The Spaces of a group show their primary's pinned tabs, and one pinned tab opens the same page in each. To give each Space pinned tabs of its own, turn on **Separate Pinned Tabs** on the Browsing page of any Space in the group. The switch applies to the whole group.

<GuideScreenshot
  src="/img/guides/sub-spaces/separate-pinned-tabs.png"
  alt="Work's Browsing page in Settings, with the Separate Pinned Tabs switch off and Keeps the Group set to Client A"
  caption="Separate Pinned Tabs is on the Browsing page of each Space in a group."
/>

## Make a Sub-Space

On Mac, open Settings and right-click a Space in the sidebar, or open the **…** menu on its page, then choose **New Sub-Space**. You can also click **+** after the crests on a group's page, or right-click an empty part of the browser sidebar. The new Sub-Space copies the Space's look and settings, starts with one Start Page tab, and opens on its own page in Settings.

On iPhone and iPad, open **Settings → Spaces**, touch and hold a Space, then choose **New Sub-Space**.

## Add an existing Space to a group

Right-click the Space in the Settings sidebar, or open the **…** menu on its page, choose **Make Sub-Space of**, then choose the group. On Mac you can also drag the Space in the Settings sidebar onto another Space, or among a group's Sub-Spaces. On iPhone and iPad, touch and hold the Space in **Settings → Spaces**.

<GuideScreenshot
  src="/img/guides/sub-spaces/make-sub-space-menu.png"
  alt="The … menu on Personal's page in Settings, with Make Sub-Space of open and Work listed"
  caption="Make Sub-Space of lists the groups a Space can join."
/>

Crest asks first. The Space keeps its tabs and starts using the group's sign-ins, history and extensions. Its own sign-ins and website data stay on this device, unused, and come back if you separate it.

<GuideScreenshot
  src="/img/guides/sub-spaces/make-sub-space.png"
  alt="A confirmation asking to make Personal a Sub-Space of Work, with Make Sub-Space and Cancel buttons"
  caption="Crest says what a Space will use before it joins a group."
/>

A Space that leads Sub-Spaces can't join another group, and private windows can't have Sub-Spaces.

## Switch between Sub-Spaces

Sub-Spaces switch like any other Space. A group's Spaces sit together, primary first, and the Space picker outlines each group. **Control-1** through **Control-9** select Spaces by position, counting Sub-Spaces.

<GuideScreenshot
  src="/img/guides/sub-spaces/space-picker.png"
  alt="The Space picker with an outline around Work, Client A and Client B, and Personal on its own"
  caption="The Space picker outlines each group."
/>

To move a whole group, drag its primary. On Mac, dragging a Sub-Space among its own group's Sub-Spaces reorders it.

## Separate a Sub-Space

Right-click the Sub-Space in the Settings sidebar, or open the **…** menu on its page, and choose **Separate from "Primary"…**, or drag it out of its group in the Settings sidebar on Mac. On iPhone and iPad, touch and hold it in **Settings → Spaces**. The Space keeps its tabs and goes back to its own sign-ins, website data and extensions.

A primary can't be separated. To end a group, separate or delete each of its Sub-Spaces.

## Delete a Space in a group

Deleting a Sub-Space deletes its tabs. Its group keeps the sign-ins, history and passwords it shares.

Deleting a primary asks which of its Sub-Spaces keeps the group, with its sign-ins, history, passwords and pinned tabs. To delete everything instead, choose **Delete "Primary" and Its Sub-Spaces…**. Unlock a locked group before you delete its primary.

<GuideScreenshot
  src="/img/guides/sub-spaces/delete-primary.png"
  alt="A confirmation for deleting Work, with a menu choosing Client A to keep the group"
  caption="Deleting a primary hands its group to the Sub-Space you choose."
/>

## Open a page under another account

To open a link with another Space's sign-ins on Mac, right-click it and choose a Space from **Open Link in**. The page opens in a Quick Window in that Space's session, so you can see the same site under another account. Choose **Keep** to move it into that Space. **Open This Page in** in Site Controls does the same for the page you're on. The Spaces of one group are listed together.

## Use Sub-Spaces on older devices

Devices that run an earlier version of Crest keep syncing. They show each Sub-Space as a Space on its own, signed out, until they update. The first group you make reminds you to update Crest on your other devices.

## Import groups from Arc and Zen

Importing from Arc brings the Spaces of each Arc profile in as one group, led by the profile's first Space. Importing from Zen does the same for each profile's workspaces. Zen workspaces that open their tabs in one container share that container's sign-ins instead, so they come in as a group of their own.

If the review sends one Space of a group into a Space you already have, the rest of the group become Sub-Spaces of that Space's group, and its primary keeps leading it. They take the group's settings and its primary's pinned tabs. Imported passwords go to the group's primary.

The review outlines each group and says which group each Space joins. Choose **Separate** to bring a Space in on its own. See [Move your browser data to Crest](../getting-started/move-to-crest.md).
