# CrestEngines/Chromium/Apple

The Swift side of the Chromium engine on the Mac: `ChromiumEngine` and its
deferred runtime, the page adapter and native page view, the application and
shell hooks Chromium's Mac shell calls, the presentation of each engine event,
extensions UI, and the Chromium settings and site sections. The folder is
compiled only into the Chromium host frameworks, never the WebKit-only or
mobile apps.

## Goal

Host Chromium's pages, popups and system sign-in in the windows Crest's shell
opens, and turn engine events into engine-neutral page events, without any
shared code naming a Chromium type.

## Contents

| Path | What it is |
| --- | --- |
| `ChromiumEngine.swift`, `ChromiumRuntime.swift`, `ChromiumRuntimeShell.swift` | The default engine, its runtime that loads Chromium on first use, and the shell that forwards only engine work |
| `ChromiumPageAdapter.swift`, `ChromiumNativePage.swift` | One page's adapter and the view that hosts it |
| `ChromiumComposition.swift`, `ChromiumApplication.swift`, `ChromiumApplicationDelegate.swift` | The native application with a deferred Chromium runtime, and its AppKit launch hooks |
| `ChromiumMacUI.swift`, `ChromiumShellHost.swift` | What Chromium's Mac shell asks of Crest's UI, and what Crest's shell asks of Chromium |
| `BrowserEngineRegistration+Chromium.swift` | Chromium's registration and declared capabilities |
| `ChromiumInternalURL.swift`, `ChromiumSelectionTranslation.swift`, `ChromiumProfileNotifications.swift` | `crest://` addresses for engine pages, selection translation, per-profile web notifications |
| `CrestChromiumHost.h` | The Objective-C bridging header the host frameworks build with |
| `EnginePresentations/` | One `+ChromiumEngine` file per engine event (`EnginePresentation`), each presenting itself on `ChromiumEngine` |
| `Extensions/` | Extension controls, store, side panels, `ExtensionCommand`, the Chrome Web Store install view, the extension settings pane |
| `Extensions/Presentation/` | Extension toolbar, pinned strip, popup anchors, badges, context menus, install pages |
| `Presentation/` | The Chromium feature-flag settings pane and site sections |

## Depends on

`CrestShared` (the engine port, `BrowserEngineRegistration`, shared
features), `CrestMac`, `CrestContracts/include`, the Chromium host built from
`../Overlay/` and `../Patches/`. Compiled by the `CrestChromiumUI` and
`CrestChromiumUIProduct` targets (`project.yml`), which take engine-specific
files from here in place of the ones they exclude from `CrestShared` and
`CrestMac`.

## Rules

- `CrestChromiumHost.h` is an engine input: changing it needs a maintainer-published engine; say so in the pull request (`AGENTS.md`, "Published Chromium engine").
- Every other file here reuses the published engine (`AGENTS.md`, "Published Chromium engine").
- The binding reports what Chromium did; the core decides rules and owns state (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Ownership").
- A Space is one profile; a private window is a fresh incognito profile with no installed extensions (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Ownership").
- Extensions run only in Chromium (`Documentation/ARCHITECTURE.md`, introduction); an extension's popup opens as a tab, and side panels and DevTools dock inside the window (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Ownership").
- A page another page opens stays on its opener's engine (skill, "Architecture").
- Capabilities in `BrowserEngineRegistration+Chromium.swift` describe what the binding really does (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Ownership").
- Never launch the unbranded Chromium build directly; its keychain item prompts (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Builds and packaging").

## Read next

`Documentation/Architecture/EngineAbstractionCompletion.md` ("How each engine
behaves"), `../README.md`, then `ChromiumEngine.swift`.
