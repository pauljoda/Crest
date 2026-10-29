# QuickWindow

Quick Window: the small transient window a link from another app, or a window
a page asked for (such as a sign-in popup), opens in. It uses a real Space's
profile and engine, and its page can be promoted into a normal window's tab
in a chosen Space or dropped.

## Goal

Popups and outside links never become windows or tabs the person did not
choose; the person keeps or drops each one.

## Contents

| Path | What it is |
| --- | --- |
| `BrowserQuickWindowView/Components/` | Content, toolbar, address control (security icon, source Space indicator), destination control and Space picker, page surface (live, lookup start, released page), unlocked content, window surface and backdrop |
| `BrowserQuickWindowView/Models/` | `BrowserQuickWindowModel`: the window's page, request and closing |
| `BrowserQuickWindowView/Services/` | `BrowserQuickWindowRequestLifecycle` |
| `Components/` | The AppKit geometry bridge and host view |
| `Models/` | `BrowserQuickWindowBrowsingContext`: the browser and pages a Quick Window promotes into |
| `Support/` | `BrowserQuickWindowLayout` and the preview fixture |

## Depends on

`CrestMac/Infrastructure/Pages/` (`BrowserPagePool` hands a page-made window
over through `CrestMac/Features/Browser/BrowserRootView/Components/BrowserPopupWindowPresentation.swift`),
and the core's link decisions through `BrowserStore`. Windows
are opened by `CrestMac/App/Shell/BrowserMacWindows.swift`.

## Rules

- A window a page asks for opens as a Quick Window over the opener's window, in the opener's Space and engine, never as a window of its own (skill, "Windows and UI"; `Documentation/ARCHITECTURE.md`, "Windows on macOS").
- Any new window from a Quick Window loads in that Quick Window (`Documentation/LinkOpeningPolicy.md`, "Link opening" gesture table).
- The core decides where a link or a page-made window goes; nothing here infers a gesture the page did not report (`Documentation/LinkOpeningPolicy.md`, "Link opening").
- A page opened by another page stays on its opener's engine, whatever the site's engine rule (skill, "Architecture"; `Documentation/LinkOpeningPolicy.md`, "Link opening").
- Its address field claims the title-bar guard so the window does not move under a press (`Documentation/ARCHITECTURE.md`, "Windows on macOS").
- An unexpected window during validation is a defect (skill, "Windows and UI").

## Read next

`Documentation/LinkOpeningPolicy.md`, `HelpCenter/docs/browsing/peek-and-quick-window.md`,
then `CrestMac/Features/QuickWindow/BrowserQuickWindowView/Models/BrowserQuickWindowModel.swift`.
