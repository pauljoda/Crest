# CrestShared/Features/Navigation

The page a tab shows when a navigation fails: a status icon, headline,
suggestions, the actions a person can take, and technical details, laid out
from the page's `PageFailure` as the core reports it.

## Goal

One failure page for both engines and both shells, built from the failure the
core recorded rather than from an engine's error.

## Contents

| Path | What it is |
| --- | --- |
| `BrowserNavigationFailureView/` | The failure view: content, headline, status icon, suggestions, actions and technical details; layout and presentation models; metrics, appearance, `PageFailure` URLs and a preview fixture |

## Depends on

The page's state in the core (`CoreState.pages`) through `BrowserStore`.
Shown by `CrestMac/Features/Browser/` (the web page failure overlay) and by
`CrestMobile/Features/Browser/` and `CrestMobile/Features/SplitView/`.

## Rules

- The core decides failure-recovery rules; the view presents them (`Documentation/ARCHITECTURE.md`, "Engine boundary").
- A retry or new address goes through the core's `Navigate` (same).
- Shared code never reads WebKit or Chromium errors directly (skill, "Architecture").
- No tests for copy or layout; review the page in the running app (skill, "Tests").

## Read next

`Documentation/ARCHITECTURE.md` ("Engine boundary"), then the page surface of
the shell being changed.
