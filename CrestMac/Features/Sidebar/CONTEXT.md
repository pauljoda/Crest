# Sidebar

The Mac side of the sidebar: AppKit pointer, middle-click and back/forward
mouse handling, drag sources and lift previews, the site control button by
the address, emoji entry, and the bindings that connect the shared sidebar's
ports to the window's page pool. The sidebar itself is
`CrestShared/Features/Sidebar/`.

## Goal

The shared sidebar behaves natively on a Mac without forking any of its
behavior.

## Contents

| Path | What it is |
| --- | --- |
| `BrowserSidebar/` | Loaded content and Space pages, the sidebar's address band and tab list scroll, pointer navigation, saved-location restore |
| `BrowserSiteControlButton/` | The site control by the address: security button, popover, quick actions, site data, blocked-popup notice |
| `Components/` | Tab selection targets and monitor, native emoji field, and the AppKit seams in `BrowserIconCustomization/`, `BrowserSidebarDrag/` (drag sources, lift previews, autoscroll), `BrowserSidebarNavigationControls/` (history menus), `BrowserSidebarRow/` (auxiliary click, tab promotion), `BrowserSpaceSwitcher/` |
| `Models/` | Background and mouse-button actions, dispositions and pointer scope |
| `Support/` | Middle-click gesture, mouse navigation target, and the `+PagePool` bindings of the shared sidebar's navigation, page access, tab actions and utilities |
| `BrowserSidebarInteractionState+LinkNotices.swift` | Confirms a link or palette row that opened behind the page in use |

## Depends on

`CrestShared/Features/Sidebar/` (the canonical sidebar, `BrowserSidebarInteractionState`),
`CrestShared/Features/Tabs/` and `CrestShared/Features/Spaces/`,
`CrestMac/Infrastructure/Pages/` (`BrowserPagePool`). Composed by
`CrestMac/Features/Browser/`.

## Rules

- Add a file here only for a genuine platform seam, such as an AppKit gesture or system adapter or a `BrowserPlatform*` same-name pair; never fork the shared sidebar's behavior (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- Reorders, moves, folders and closes go through core intents; never mutate `BrowserStore.session` (skill, "Architecture").
- Each window and browsing mode owns its own `BrowserSidebarInteractionState` for drags and reorder geometry (`Documentation/ARCHITECTURE.md`, "Platform shape").
- Sizing and reveal come from `BrowserInteractionCapabilities` and shared policy, not a device check (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- "Opened in background" feedback is a notice, not a sheet (skill, "Windows and UI").

## Read next

`CrestShared/Features/Sidebar/CONTEXT.md`, `Documentation/ARCHITECTURE.md`
("Platform shape"), then `CrestMac/Features/Sidebar/Support/` for how a shared port reaches the page pool.
