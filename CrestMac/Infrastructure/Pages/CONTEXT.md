# Pages

The Mac page host: `BrowserPage` (one engine-neutral page and its AppKit
view), `BrowserPagePool` (a window's pages and the focused card), the pool
registry, the engine adapter seam, the web host view that moves a page
between windows, the title-bar guard, and the events an engine reports about
its page.

## Goal

A page is the same object whichever engine draws it; the engine reaches it
only through its adapter, its events and the core's page state.

## Contents

| Path | What it is |
| --- | --- |
| `BrowserPage.swift`, `BrowserPage+*.swift` | The page and its Mac behavior: downloads, engine links, native presentation, prompts, site data, sharing, web notifications |
| `BrowserPagePool.swift`, `BrowserPagePool+*.swift` | A window's pages: active-page matching, Space selection, screen sharing; hands page-made windows to a Quick Window |
| `BrowserPagePoolRegistry.swift`, `BrowserPagePoolWindowRuntime.swift` | Every open window's pool, and a pool's window runtime |
| `BrowserPageEngineAdapter.swift`, `EngineHostedPage+Desktop.swift` | The desktop half of an engine's adapter for one page |
| `BrowserPlatformPage.swift`, `BrowserPlatformWebView.swift`, `BrowserPlatformTransientPageLease.swift` | The shared seams resolved to the Mac's concrete types |
| `BrowserWebHostView.swift` | The `NSView` that presents a page's view in whichever window shows it |
| `BrowserTitleBarPointerTracker.swift`, `BrowserWindowTitleBarGuard.swift` | Keep a window from moving while the pointer is on a page under the title bar |
| `BrowserPageContextMenuAction.swift` | Crest's actions ahead of the engine's page menu |
| `BrowserEngineInfoBar.swift`, `BrowserDeveloperViewport.swift`, `BrowserPageSnapshotImage.swift` | Engine info bars, developer viewport presets, page snapshots |
| `EngineEvents/` | `BrowserPageEngineEvent` and one type per event: navigation, loading, title, URL, favicon, fullscreen, media, share sources, info bars, popups blocked, notifications, process termination, closing |

## Depends on

`CrestShared/Infrastructure/Pages/` (`BrowserPageHost`, page ownership),
`CrestShared/Infrastructure/Engines/` (`BrowserPageEngine`, `EnginePageReporter`),
the core's `Pages` read model. Engine adapters: `CrestMac/Infrastructure/WebKit/`
and `CrestEngines/Chromium/Apple/`. Consumed by `CrestMac/Features/`.

## Rules

- Shared code never calls an engine API; it talks to `BrowserPageEngine` through the page's adapter (skill, "Architecture"; `Documentation/ARCHITECTURE.md`, "Engine boundary").
- A page's address, title, loading, security and history live in the core's `Pages`, reported once per turn through `EnginePageReporter`; progress, find, hover, fullscreen and zoom stay on the page (`Documentation/ARCHITECTURE.md`, "Engine boundary").
- An engine event is a new type with its own `apply(to:)`, never a switch (`CrestMac/Infrastructure/Pages/EngineEvents/BrowserPageEngineEvent.swift`; skill, "Code style").
- Each tab has one runtime owning its live page; the focused window hosts the live view (`Documentation/ARCHITECTURE.md`, "Windows on macOS").
- A window a page makes goes to a Quick Window in the opener's engine and Space (skill, "Windows and UI").
- While the pointer is on a page under the title bar, `BrowserTitleBarPointerTracker` claims `BrowserWindowTitleBarGuard` so a press does not drag the window; Move & Resize, tiling and display changes still move it (`Documentation/ARCHITECTURE.md`, "Windows on macOS").
- Memory pressure never unloads a page that has not shown a document (`Documentation/LinkOpeningPolicy.md`, "Loading and residency").

## Read next

`Documentation/ARCHITECTURE.md` ("Engine boundary", "Windows on macOS"),
`Documentation/Architecture/EngineAbstractionCompletion.md`, then
`CrestMac/Infrastructure/WebKit/CONTEXT.md` or `CrestEngines/Chromium/CONTEXT.md`.
