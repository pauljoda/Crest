# CrestMac

The macOS app: scene and window composition, the Mac shell, Mac-only features
such as Quick Window and software updates, the WebKit page host, AppKit and
system adapters, and the agent bridge. It composes `CrestShared` and both
engines.

## Goal

A single-window Mac browser whose platform code is only the seams AppKit and
macOS require; behavior stays shared.

## Contents

| Folder | What it is |
| --- | --- |
| `App/` | `BrowserMacApplication`, the window scene, the shell either engine product runs (`Shell/`), window coordinator and close gate, the agent tool catalog (`Agents/`), the WebKit-only entry (`Composition/`) ([CONTEXT](App/CONTEXT.md)) |
| `Features/` | Mac presentation: AppIcon, Browser, Chrome, Commands, Credentials, Downloads, ExtensionSidePanel, NativeTabs, Onboarding, QuickWindow, RecentTabSwitcher, Settings, Sidebar, SiteSettings, SoftwareUpdates, Spaces, SplitView, Tabs, TransientBrowsing, Utilities, Window, WindowAppearance ([CONTEXT](Features/CONTEXT.md)) |
| `Infrastructure/` | Mac adapters: Agents, BrowserDefaultBrowser, BrowserHostedWebNotifications, BrowserPasskeyAccess, BrowserShortcuts, CloudSync, Downloads, Engines, MediaSessions, PageActions, Pages (the page host and engine events), SystemPermissions, WebKit, `BrowserDialogPresenter.swift` ([CONTEXT](Infrastructure/CONTEXT.md); Agents is the agent socket) |
| `DesignSystem/` | Mac-only metrics, colors and modifiers |
| `Configuration/`, `Resources/` | Entitlements and plist settings; engine logos |

## Depends on

Compiled as source with `CrestShared` and `CrestAgents` into the Mac targets
in `project.yml` (`Crest`, `CrestNativeCore` and the Chromium host
framework), with the Sparkle package. It reaches `CrestCore` through
CrestShared's core adapters (`CrestShared/Infrastructure/Core/`).
`CrestEngines/Chromium/Apple/` is compiled beside it in the Chromium host
framework and plugs into the shell through `BrowserMacEngineHost`. Of the
Swift source roots, only this one may import AppKit, CoreServices and
SecurityInterface (`Scripts/check-architecture.py`).

## Rules

- Never create a window the person did not ask for; page and extension popups open as a Quick Window in the opener's engine and Space (skill, "Windows and UI").
- Informational feedback goes through `BrowserChromeState.showNotice` (`CrestMac/Features/Browser/Models/`), not alerts or sheets (skill, "Windows and UI").
- A platform file exists only for a genuine seam; never fork a shared component's behavior (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- Validation launches use `CREST_ISOLATED_SESSION=1` (`Documentation/RepositoryGuardrails.md`, "Isolated validation sessions").
- Quit, unregister and delete every test copy of Crest before handing off (skill, "Verification and reporting").
- Visual changes are checked in the running app and shown in the pull request, never tested (skill, "Tests", "Verification and reporting").

## Read next

`Documentation/ARCHITECTURE.md` ("Windows on macOS"),
`Documentation/LinkOpeningPolicy.md`, then the feature folder.
