---
title: Install and update Crest for Mac
description: Download Crest directly, install it in Applications, and understand automatic updates.
slug: /install-and-update-mac
keywords: [download, install, update, macOS, GitHub Releases, Sparkle]
---

# Install and update Crest for Mac

Crest for Mac is distributed directly as a signed and notarized Apple silicon app. iPhone and iPad builds continue through TestFlight.

## Install the latest Mac release

1. Open the [latest stable Crest release](https://github.com/pauljoda/Crest/releases/latest).
2. Open the newest release and download its `.dmg` file.
3. Open the disk image, then drag Crest into **Applications**.
4. Eject the disk image and open Crest from Applications.

Keeping Crest in Applications gives macOS and the updater one stable installed location. If Gatekeeper reports that the app cannot be verified, do not bypass the warning; download the current release again from the official Releases page.

## Automatic updates

Crest uses Sparkle to check for signed updates from inside the installed app. When an update is available, review the release, install it, and let Crest relaunch. Your Spaces and browsing data remain in their normal app storage rather than inside the application bundle.

You can also open the app menu and choose **Check for Updates**. A manual check uses the same signed update channel as the automatic check.

## Stable and Nightly

Use **Settings → General** to choose the update channel:

- **Stable** is the normal public release cadence.
- **Nightly** receives newer builds sooner and can change more frequently.
- **Development** follows the latest signed public `main` build and can change several times a day.

Changing channels changes which future update is offered; it does not move or duplicate your profile.

## iPhone and iPad

Install the mobile beta through [TestFlight](https://testflight.apple.com/join/vV1CM49Q). If iCloud sync is enabled, the same durable Space structure can follow you between Mac, iPad, and iPhone.
