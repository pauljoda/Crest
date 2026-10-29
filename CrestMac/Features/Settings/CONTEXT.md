# Settings

The Mac Settings page: `BrowserSettingsView`, its sidebar and destination
catalog, the native grouped-form container for shared panes, and the panes
only the Mac has (engines, agents, keyboard shortcuts, system privacy and
permissions, WebKit feature flags, app icon). Shared panes live in
`CrestShared/Features/Settings/`.

## Goal

Settings is a native tab in the browsing canvas whose shared panes look like
macOS, with Mac-only panes added beside them rather than forked.

## Contents

| Path | What it is |
| --- | --- |
| `BrowserSettingsView.swift` | The Settings page: sidebar, destinations, Space pages |
| `BrowserAgentsSettingsPane/` | Settings › Agents: turning agents on and the Spaces they may reach |
| `BrowserEngineSettingsPane/` | Default engine and per-site engine rules: option cards and the rule editor |
| `BrowserShortcutSettingsView.swift`, `BrowserShortcutSettingsView/` | Keyboard shortcut list, recorder and controls |
| `BrowserWebKitFeatureFlagSettingsPane/` | WebKit feature flag list and controls over `CrestMac/Infrastructure/WebKit/FeatureFlags/` |
| `BrowserPlatformLinkRouteEditor/` | The Mac half of the shared link route editor (same-name pair) |
| `BrowserSystemPrivacySettingsPane.swift`, `BrowserSystemPermissionSettingsSection.swift` | What macOS lets Crest reach, and each Space's privacy |
| `BrowserPlatform*.swift` (top level) | Mac halves of shared sections: app icon, look-and-feel reset, palette drag, search engine presentation |
| `Components/` | Pane container, column layout, settings sidebar and pages, Space editor and Space page, build header, developer toolbar, Picture in Picture and software update sections |
| `Forge/` | The Forge's step bar as a native segmented control |
| `Models/` | Settings navigation and tab state, destination and Space requests, system permissions and their controller |
| `Support/` | `BrowserPlatformSettingsDestinationCatalog` and sidebar tints |

## Depends on

`CrestShared/Features/Settings/` (shared panes and models), the core's
preferences through `BrowserStore`, `CrestMac/Infrastructure/SystemPermissions/`,
`CrestMac/Infrastructure/WebKit/FeatureFlags/`. Opened as a native tab
through `CrestMac/Features/NativeTabs/BrowserMacSettingsTabContent.swift`.

## Rules

- Behavior preferences belong to the core and change through intents; only appearance preferences stay in Swift (skill, "Architecture").
- Per-site and default engine rules apply only to navigations a person starts (skill, "Architecture").
- Settings opens in the browsing canvas, not a separate window or sheet, on the Mac (`Documentation/ARCHITECTURE.md`, "Platform shape"; `Documentation/NativeTabs.md`, "Loaded state").
- Settings in a temporary window edits the source workspace's profile (`Documentation/NativeTabs.md`, "Loaded state").
- A Mac file here is a genuine platform seam, such as a `BrowserPlatform*` same-name pair or a system adapter; never a fork of a shared pane (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- Copy is minimal and native; no tests for settings-pane structure or copy (skill, "Writing", "Tests").

## Read next

`CrestShared/Features/Settings/`, `Documentation/NativeTabs.md`, then
`CrestMac/Features/Settings/Support/BrowserPlatformSettingsDestinationCatalog.swift`.
