# CrestMobile/Features/Settings

The touch Settings shell: `MobileBrowserSettingsView`, which shows the shared
settings panes as a destination list and page at compact width and as a
split layout at regular width, plus the UIKit and iOS seams the shared panes
leave to the platform (Home Screen icon, palette drag, Forge step bar).

## Goal

Every shared settings pane on iPhone and iPad in native forms, with only the
destinations whose subject exists on the device.

## Contents

| Path | What it is |
| --- | --- |
| `MobileBrowserSettingsView.swift` | The settings root a native tab or sheet shows |
| `MobileBrowserSettingsView/Components/` | Compact and regular layouts, settings content, destination list, page and row, the build header |
| `MobileBrowserSettingsView/Components/MobileSpaceSettingsView/` | Space settings: selection, customization, workspace toolbar |
| `MobileBrowserSettingsView/Models/` | `MobileSettingsDestinationFilter` (search over destinations) |
| `Support/` | `BrowserPlatformSettingsDestinationCatalog` (which destinations mobile offers), the appearance section |
| `Components/` | The pane container, the Space settings pane, Home Screen app icon views |
| `BrowserPlatformLinkRouteEditor/` | The link route editor's content and layout |
| `Forge/` | `BrowserPlatformCrestForgeStepBar`, the Forge's steps as a `UISegmentedControl` |
| `BrowserPlatform*.swift` (root) | App icon section, Look and Feel reset, palette section drag, search engine presentation |

Most `BrowserPlatform*` files pair same-name files in `CrestMac/Features/Settings/`.
The settings state lives in `../NativeTabs/BrowserMobileSettingsTabContent.swift`.

## Depends on

`CrestShared/Features/Settings/` (the panes), `BrowserStore`,
`MobileBrowserPageStore`, `BrowserSpaceAccessController`. Opened from
`../Browser/` and `../NativeTabs/`.

## Rules

- Settings sits in the browsing canvas at regular width and uses a sheet only at compact width; the current layout decides, including after a resize (`Documentation/ARCHITECTURE.md`, "Platform shape").
- Panes are shared; this tree adds only the form container and platform seams (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- A setting that changes browser behavior goes through a core intent; only appearance preferences stay in Swift (skill, "Architecture").
- Minimal native copy through `String(localized:)`; no subtitles for what the UI shows (skill, "Writing").
- Settings-pane structure and copy are reviewed in the running app, never tested (skill, "Tests").
- An `@AppStorage` view separates saved preferences from visual content before it gets a preview (`Documentation/RepositoryGuardrails.md`, "Feature organization").

## Read next

`CrestShared/Features/Settings/`, then `MobileBrowserSettingsView.swift` and
`Support/BrowserPlatformSettingsDestinationCatalog.swift`.
