# CrestShared/Features/Settings

The settings both shells present. `BrowserSettingsDestination` is the one
catalog of panes (name, glyph, search words); each shell keeps its own
navigation and `BrowserSettingsDestinationRouter` picks a destination's pane.
Panes cover general, tabs, search, links, look and feel, Spaces, sync,
privacy, passwords, engines and extensions, advanced and about.

## Goal

One pane per destination, shared by macOS and iOS, editing core preferences
through intents and appearance preferences locally.

## Contents

| Path | What it is |
| --- | --- |
| `Browser*SettingsPane.swift`, `Browser*Section.swift` | Single-file panes and sections: general, tabs, look and feel, privacy, about, durable tabs, translation, Space deletion |
| `BrowserSpaceAccessView.swift`, `BrowserSyncSettingsView.swift` | The locked-Space access screen and the sync view |
| `BrowserAdvancedSettingsPane/` | Advanced settings and setup actions; hosts `DataPortability/` |
| `BrowserLinkSettingsPane/` | Link routing, external-link destination, Peek and Quick Window preferences |
| `BrowserPasswordSettingsPane/` | Crest Passwords list, detail and passkey access |
| `BrowserPrivacySettingsPane/` | Privacy sections: content blocking, data retention, website data, saved site permissions, clearing data |
| `BrowserSearchSettingsPane/` | Search providers and rules |
| `BrowserPlatformLinkRouteEditor/` | A link route editor whose content each platform supplies |
| `BrowserSpaceSettingsSections/` | Per-Space sections: browsing, downloads, access policy |
| `BrowserSpaceAddButton/`, `BrowserSpaceOrderControls/` | Adding and ordering Spaces |
| `Components/` | Pane chrome, destination router, look-and-feel groups and preview, private Space access, sync diagnostics, engine extensions |
| `Models/` | Destinations, appearance mode and presets, device appearance store, about information |
| `Support/` | `BrowserStore` settings bindings, canvas, Space appearance and access layout |

## Depends on

`BrowserStore`, `BrowserSpaceAccessController`, `BrowserEngineRegistration`,
the preference and permission stores in `CrestShared/Application/`
(`BrowserSearch/`, `BrowserAppPreferences/`, `BrowserLinkPreferences/`,
`BrowserSitePermissions/`), `Credentials/`, `DataPortability/`, `Spaces/`,
`Sidebar/`, `Chrome/`. Presented by `CrestMac/Features/Settings/` and
`CrestMobile/Features/Settings/`.

## Rules

- Behavior preferences are core state: change them with an intent; only appearance preferences stay in Swift (skill, "Architecture").
- A destination's `name` is a shipped contract behind accessibility identifiers; never rename one (`CrestShared/Features/Settings/Models/BrowserSettingsDestination.swift`).
- Settings sits in the browsing canvas at regular width, a sheet only at compact width (`Documentation/ARCHITECTURE.md`, "Platform shape").
- The capabilities an engine declares in `BrowserEngineRegistration` decide which features the UI offers (`Documentation/ARCHITECTURE.md`, "Engine boundary").
- No tests for pane structure or copy (skill, "Tests").

## Read next

`Documentation/ARCHITECTURE.md` ("Credentials and privacy", "Data and
synchronization"), then the pane's folder and its platform shell.
