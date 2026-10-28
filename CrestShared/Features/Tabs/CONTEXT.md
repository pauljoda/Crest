# CrestShared/Features/Tabs

How a tab is drawn wherever it appears: its favicon with engine badge, its
status marks (media playing, an agent at work, a shared page, and the
actions each offers), the pinned-tab grid, the selection glow and appearance
surface, folder colors, and closing a durable (saved or pinned) tab.

## Goal

One tab presentation for sidebar rows, the pinned grid, previews and
onboarding, so a tab looks and acts the same everywhere.

## Contents

| Path | What it is |
| --- | --- |
| `TabFaviconView/` | Favicon view, engine badge, Start Page mark, and the favicon image cache, loader and decoder |
| `Components/PinnedTabGrid/` | Pinned tabs as a grid of tiles |
| `Components/TabStatus/` | Status badge, control, equalizer and their hosts |
| `Components/` (files) | Selection glow and tab appearance surface |
| `Models/` | Tab status, its source, surface and actions; folder color palette and choice |
| `Services/` | `BrowserDurableTabCloseAction` |
| `Support/` | `TabState` and `TabStateModel` presentation |
| `BrowserFolderColorPicker.swift` | The folder color picker |

## Depends on

The core's tab read model, `Infrastructure/Favicons/`, `DesignSystem/`. Used
by `Sidebar/`, `Settings/`, `Spaces/`, `Onboarding/`, `Utilities/` and
the platform `Tabs/` folders.

## Rules

- Closing, pinning and moving tabs are core intents; the core decides whether a page may go (skill, "Architecture").
- Favicon fetching stays inside the Space's profile, credential-free for public fallback (`Documentation/ARCHITECTURE.md`, "Engine boundary").
- Native tabs share every tab path; see `Documentation/NativeTabs.md`.
- No tests for symbols, tints or layout (skill, "Tests").

## Read next

`Documentation/NativeTabs.md`, then `Sidebar/` for the rows that host these
views.
