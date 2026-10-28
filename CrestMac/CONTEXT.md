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
| `App/` | `BrowserMacApplication`, window scenes, composition, the shell, engine-move notices |
| `App/Agents/` | The agent tool catalog and calls (tabs, pages, windows, approvals) behind `CrestAgents` |
| `Features/` | Mac presentation: Browser, Sidebar, Settings, Onboarding, QuickWindow, SplitView, SoftwareUpdates, SiteSettings, ... |
| `Infrastructure/Pages/` | The Mac page host and engine events |
| `Infrastructure/WebKit/` | Mac WebKit integration |
| `Infrastructure/` (others) | Shortcuts, downloads, passkeys, notifications, cloud sync, system permissions |
| `DesignSystem/` | Mac-only metrics, colors and modifiers |
| `Configuration/`, `Resources/` | Entitlements and plist settings; engine logos |

## Depends on

`CrestShared`, `CrestCore` (through CrestShared), `CrestEngines/Chromium`,
`CrestAgents`. AppKit, CoreServices and SecurityInterface are allowed only in
this tree (`Scripts/check-architecture.py`).

## Rules

- Never create a window the person did not ask for; page and extension popups open as a Quick Window in the opener's engine and Space (skill, "Windows and UI").
- Informational feedback goes through `BrowserChromeState.showNotice` (`Features/Browser/Models/`), not alerts or sheets (skill, "Windows and UI").
- A platform file exists only for a genuine seam; never fork a shared component's behavior (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- Validation launches use `CREST_ISOLATED_SESSION=1` (`RepositoryGuardrails.md`, "Isolated validation sessions").
- Quit, unregister and delete every test copy of Crest before handing off (skill, "Verification and reporting").
- Visual changes are checked in the running app and shown in the pull request, never tested (skill).

## Read next

`Documentation/ARCHITECTURE.md` ("Windows on macOS"),
`Documentation/LinkOpeningPolicy.md`, then the feature folder.
