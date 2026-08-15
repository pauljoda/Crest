---
title: Turn Crest Passwords on or off per Space
description: Control Crest-owned password suggestions, generation, and save prompts independently for every Space.
slug: /crest-passwords-per-space
sidebar_label: Crest Passwords
sidebar_position: 6
keywords: [Crest Passwords, password settings, Space, Keychain, turn off]
---

# Turn Crest Passwords on or off per Space

Crest Passwords are private to the Space that owns them. You can stop using Crest-owned suggestions, generation, and save prompts in one Space without deleting its saved passwords or changing another Space.

## Change the setting

1. Open **Crest Settings → Passwords**.
2. Under **Space**, choose **Passwords for** and select the Space you want to change.
3. Under **Crest Passwords**, turn **Use Crest Passwords in this Space** on or off.

When Crest Passwords is off, saved passwords remain in that Space until you delete them. Turning the setting back on makes them available to matching sites again.

## Related controls

When Crest Passwords is on, supported Mac builds can also show:

- **Sync with iCloud Keychain**, which updates whether existing and future Crest credentials in that Space synchronize through the system Keychain.
- **Offer a copy to Passwords**, which lets the system Passwords app ask separately for a copy after Crest saves in the Space.

System Passwords and passkeys are provider-managed and may appear in any Space for a matching site. They are separate from Crest Passwords’ Space-local records.

:::info What turning it off does not do
It does not delete saved passwords, export them, move them to another Space, or place password values in CloudKit session data.
:::

Private Spaces must be unlocked before Crest reveals account and site metadata or changes their password settings.
