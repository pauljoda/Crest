# CrestShared/Features/Utilities

A Space's utility lists: Archive, History and Downloads. Each is a
`BrowserUtilitySurface` that carries its title, search prompt, filters and
items; `BrowserUtilityListContent` draws any of them with search, filters,
time sections, rows and download actions.

## Goal

One list component for the three surfaces, shown in the Mac sidebar and in
the mobile sidebar, Archive and History views.

## Contents

| Path | What it is |
| --- | --- |
| `BrowserUtilityListContent.swift` | The list view for a surface |
| `BrowserUtilityListContent/` | Its rows, search toolbar, filter menu, fan control, download status and row actions; list items, requests and actions; preparation, reconciliation and clock; a preview fixture |
| `Models/` | `BrowserUtilitySurface`, filters, time sections, download destination and file opener |
| `Support/` | Download row presentation, utility text and accessibility identifiers, download progress |

## Depends on

The core's archived tabs, history entries and `DownloadState` through
`CrestShared/Infrastructure/Core/`, `BrowserStore`, `CrestShared/Domain/`,
`Tabs/` (favicons), `Sidebar/` and `Chrome/` (metrics and layout),
`DesignSystem/`. Coordinated by
`Sidebar/Services/BrowserSidebarUtilityCoordinator.swift`; hosted by
`CrestMac/Features/Sidebar/`, `CrestMobile/Features/Sidebar/`,
`CrestMobile/Features/Archive/`, `CrestMobile/Features/History/` and
`CrestMobile/Features/Downloads/`.

## Rules

- A surface's `name` is how the selected surface is remembered; never change one (`CrestShared/Features/Utilities/Models/BrowserUtilitySurface.swift`).
- History and archive are part of a Space's boundary (`Documentation/ARCHITECTURE.md`, "Space isolation"); each utility list shows one Space's items (`CrestShared/Features/Utilities/Models/BrowserUtilitySurface.swift`).
- Clearing history and archiving are core intents, never list edits (skill, "Architecture").
- Download risk decisions are a contract worth a test; list layout is not (skill, "Tests").

## Read next

`Documentation/ARCHITECTURE.md` ("Space isolation"), then
`Sidebar/Services/BrowserSidebarUtilityCoordinator.swift`.
