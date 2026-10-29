# App

The Mac application layer: `BrowserMacApplication` and its window scene, the
shell that either engine's product runs (launch and recovery, menus, Dock,
links from other apps, quit), the window coordinator and close gate, the
WebKit product's entry point, and the agent tool catalog.

## Goal

One Mac shell for both engine products; an engine supplies only what its own
host can do, through `BrowserMacEngineHost`.

## Contents

| Path | What it is |
| --- | --- |
| `BrowserMacApplication.swift`, `BrowserMacApplication+WindowRequests.swift` | The app's services, the window content every product shows, and window requests |
| `BrowserMacWindowScene.swift` | A window's scene, following the session revision without rebuilding its body |
| `BrowserEngineMoveNotices.swift` | Explains automatic engine switches for protected video and offers the move back |
| `Agents/` | `BrowserMacAgents`: the agent tool catalog and calls (tabs, pages, windows), approvals, failures and fill refusals |
| `Shell/` | `BrowserMacShell`, `BrowserMacEngineHost`, launch recovery, main menu and menu bar, Dock menu and tile, external opening, window controller and kinds, quit |
| `Services/` | `BrowserMacWindowCoordinator` (normal and temporary windows), `BrowserWindowCloseGate`, quit preparation, tab tear-off placement and window drops |
| `Models/` | `BrowserMacWindowModel` and `BrowserMacWindowRequest` |
| `Components/` | `BrowserMacWindowAttachment`: tells a window's content which AppKit window hosts it |
| `Composition/` | The WebKit product only: `CrestMain`, `CrestAppDelegate`, `WebKitShellHost` |

## Depends on

`CrestShared` (`BrowserStore`, shared features), `CrestMac/Features/` and
`CrestMac/Infrastructure/`, the tool definitions in `CrestAgents/` and the
socket in `CrestMac/Infrastructure/Agents/`. The Chromium product enters
through `CrestEngines/Chromium/Apple/ChromiumComposition.swift` instead of
`Composition/`.

## Rules

- Never create a window the person did not ask for; a window a page asks for opens as a Quick Window (skill, "Windows and UI").
- Window contents change through core intents such as `ShowSpace` and `ShowTab`, never by mutating `BrowserStore.session` (skill, "Architecture"; `Documentation/ARCHITECTURE.md`, "Windows on macOS").
- Only what one engine's host alone can do goes into `BrowserMacEngineHost`; the rest of the shell stays engine-neutral (`CrestMac/App/Shell/BrowserMacEngineHost.swift`).
- `Composition/` is compiled into the WebKit product targets only; the Chromium host framework excludes it (`project.yml`; `CrestMac/App/Composition/CrestMain.swift`).
- An agent reaches only the Spaces the person allowed, as the core's `AgentReach` answers, and every tab it touches shows its badge (`CrestMac/App/Agents/BrowserMacAgents.swift`).
- Validation launches use `CREST_ISOLATED_SESSION=1` (`Documentation/RepositoryGuardrails.md`, "Isolated validation sessions").

## Read next

`Documentation/ARCHITECTURE.md` ("Windows on macOS"), `CrestMac/App/Shell/BrowserMacShell.swift`,
and for the agent bridge `HelpCenter/docs/browsing/coding-agents.md` and `CrestAgents/`.
