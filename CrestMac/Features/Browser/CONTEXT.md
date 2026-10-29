# Browser

The Mac browser window's content: `BrowserRootView` and its layers (sidebar,
page, backdrop, title-bar controls, notices, command palette, drag previews,
Peek), the page surface each tab card draws, and the window's chrome state.

## Goal

One root view per window that composes shared feature views over the window's
page pool and hands AppKit only the seams it needs.

## Contents

| Path | What it is |
| --- | --- |
| `BrowserRootView/` | `BrowserRootView`, `BrowserRootModel` and the root's layers in `Components/`: `Backdrop/`, `Chrome/` (sidebar hover reveal), `CommandPalette/`, `DragPreview/`, `Feedback/` (notices, recent tabs), `NativeWindowControls/` (title bar surface and traffic lights), `Page/`, `Peek/`, `Sidebar/`, `Utilities/`, `WindowFocus/`; preview fixture and sidebar width persistence in `Support/` |
| `BrowserRootView/Components/BrowserPopupWindowPresentation.swift` | Gives a window's page pool the way to open a Quick Window for a window a page asked for |
| `BrowserDetailView.swift` | The detail column: the selected tab's content and the window's commands |
| `Components/` | `BrowserDetailContent/` (live, mirrored, unloaded and Start Page content), `BrowserWebPageSurface/` (page card, agent bar and pointer, info bars, failure overlay, share picker), `BrowserDeveloperToolbar/`, `BrowserLinkHoverPreview/`, `BrowserWebContentView`, find bar style |
| `Models/` | `BrowserChromeState` (sidebar reveal, full screen, `showNotice`), `BrowserNotice`, `AddressFocusAction`, `BrowserShareSourceOffer` |
| `Support/` | `PagePresentation+BrowserPage`: what a Mac page surface shows for a tab |

## Depends on

`CrestShared/Features/Browser/` and the shared feature views it composes,
`CrestMac/Infrastructure/Pages/` (`BrowserPagePool`, `BrowserPage`),
`CrestMac/Features/Sidebar/`, `CrestMac/Features/QuickWindow/`. Hosted by
`CrestMac/App/BrowserMacWindowScene.swift` and `BrowserMacApplication`'s
window content.

## Rules

- Informational feedback goes through `BrowserChromeState.showNotice` and `BrowserNoticeLayer`; alerts and sheets only when the person must decide (skill, "Windows and UI").
- A window a page asks for opens as a Quick Window over its opener's window, never a window of its own (`Documentation/ARCHITECTURE.md`, "Windows on macOS").
- The content under the title bar keeps the window from moving while the pointer is on a page; Crest's own chrome acts as the title bar (`Documentation/ARCHITECTURE.md`, "Windows on macOS").
- The focused window hosts a tab's live view; other windows show its preview (`Documentation/ARCHITECTURE.md`, "Windows on macOS").
- Keep root `body` implementations small and compose narrowly scoped views (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- Visual changes are checked in the running app with `CREST_ISOLATED_SESSION=1` and shown in the pull request (skill, "Verification and reporting").

## Read next

`Documentation/ARCHITECTURE.md` ("Windows on macOS", "Platform shape"),
`CrestMac/Infrastructure/Pages/CONTEXT.md`, then `BrowserRootView/BrowserRootView.swift`.
