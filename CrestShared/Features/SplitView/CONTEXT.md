# CrestShared/Features/SplitView

Crest's split view: an ordered row of page cards, the gaps between them and
the dividers in those gaps, card focus, placeholders, and the drop zones that
add a page to a split. `BrowserSplitColumnsView` owns geometry only; widths
come from `BrowserSplitColumnLayout` and membership from the session.

## Goal

One split layout for the Mac, the mobile shell and the Getting Started
practice window.

## Contents

| Path | What it is |
| --- | --- |
| `Components/BrowserSplitCardResizeHandle/` | Dragging a divider between cards |
| `Components/` (files) | Columns view, placeholder card, focus indicator, content drop zone and drop-card frame modifiers |
| `Models/` | Page surface presentation (a row of cards or one page), column slots, panel columns, width transaction, card move direction |
| `Support/` | Column and panel layout, layout metrics, resize space, drop-target view extension |

## Depends on

The core's `TabStateModel` and `SpaceModel` through
`CrestShared/Infrastructure/Core/`, `CrestShared/Domain/` (runtime
assignments), `Sidebar/` (reorder state for card drags), `Chrome/` (layout
and appearance), `DesignSystem/`. Hosted by `CrestMac/Features/SplitView/`,
`CrestMobile/Features/SplitView/` (whose cards place native tabs through
`NativeTabs/BrowserNativeTabHost.swift`), the platform `Browser/` roots,
`Sidebar/` and `GettingStarted/`.

## Rules

- Split membership and order are core state; the view never edits them (skill, "Architecture").
- A tab dragged between workspaces arrives without its source folder or split membership (`Documentation/ARCHITECTURE.md`, "Windows on macOS").
- Native and website cards share the split; only website members get pages (`Documentation/NativeTabs.md`, opening section).
- Name metrics and thresholds in the type that owns them (`Documentation/ARCHITECTURE.md`, "Platform shape").

## Read next

`Documentation/NativeTabs.md`, then `Sidebar/` for split group rows and the
platform `SplitView/` folder.
