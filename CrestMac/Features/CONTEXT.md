# Features

Mac presentation by user purpose: the browser window's root view and page
surface, the Mac sides of the sidebar, Settings and onboarding, Quick Window,
and the AppKit seams of shared features. Shared UI lives in
`CrestShared/Features/`; a folder here holds only what macOS needs on top.

## Goal

Every Mac feature is the shared component plus a genuine platform seam,
never a second copy of its behavior.

## Contents

| Folder | What it is |
| --- | --- |
| `Browser/` | The window's root view, page surface, chrome state and notices, developer toolbar ([CONTEXT](Browser/CONTEXT.md)) |
| `Sidebar/` | Mac sidebar seams: pointer and middle-click handling, drag lifts, site control button, page-pool bindings ([CONTEXT](Sidebar/CONTEXT.md)) |
| `Settings/` | `BrowserSettingsView` and the Mac panes: engines, agents, shortcuts, system privacy, WebKit feature flags ([CONTEXT](Settings/CONTEXT.md)) |
| `Onboarding/` | The setup window and importing from installed browsers, passwords included ([CONTEXT](Onboarding/CONTEXT.md)) |
| `QuickWindow/` | The Quick Window a page's popup or a transient link opens in ([CONTEXT](QuickWindow/CONTEXT.md)) |
| `AppIcon/` | Alternate app icon assets and the Dock tile view, also built into `CrestDockTilePlugin` |
| `Chrome/` | Command palette field, full-screen bridge and the Space pager gestures |
| `Commands/` | `BrowserMacCommand`, command actions, find and numbered selection |
| `Credentials/` | The credential clipboard and pasteboards |
| `Downloads/` | The download feedback layer and its flight path (`Feedback/`) |
| `ExtensionSidePanel/` | The extension side panel card and hosts |
| `NativeTabs/` | Mac content for native tabs: Settings and Getting Started |
| `RecentTabSwitcher/` | The recent-tab switcher, its model and its settings section |
| `SiteSettings/` | Per-site settings: engine, permissions, security, certificate |
| `SoftwareUpdates/` | Update channel, check, user driver and the release notes view |
| `Spaces/` | Space name dismissal, palette color well and symbol artwork |
| `SplitView/` | Split cards: hover, pointer, lift and focus |
| `Tabs/` | Tab equalizer, pinned-tab middle click, Getting Started icon |
| `TransientBrowsing/` | The Peek overlay, its keyboard monitor and model |
| `Utilities/` | The utility filter's menu style |
| `Window/` | Window title and accessibility |
| `WindowAppearance/` | Mac appearance and sidebar reveal and motion preferences |

## Depends on

The `CrestShared/Features/` folder of the same name where one exists, `CrestShared/DesignSystem/`
and `CrestMac/DesignSystem/`, the page pool in `CrestMac/Infrastructure/Pages/`,
the core through `BrowserStore`, and the Sparkle package (`SoftwareUpdates/`).
Composed by `CrestMac/App/`.

## Rules

- A file here exists only for a genuine platform seam; a divergence goes into a capability bit, shell input, optional closure or accessory slot, never a fork (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- Informational feedback goes through `BrowserChromeState.showNotice`, not alerts or sheets (skill, "Windows and UI").
- Reuse `crestInteractiveSurface`, `CrestChromeButtonStyle` and the tokens; no ad-hoc fills (skill, "Windows and UI").
- Previews sit beside the components that own editable UI and stay deterministic (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- User-facing strings use `String(localized:)` and the catalog (skill, "Writing").
- Appearance is reviewed in the running app and shown in the pull request, never tested (skill, "Tests", "Verification and reporting").

## Read next

`Documentation/ARCHITECTURE.md` ("Platform shape", "Windows on macOS"), then
the feature's `CrestShared/Features/` counterpart and this tree's folder.
