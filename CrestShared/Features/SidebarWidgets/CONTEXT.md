# CrestShared/Features/SidebarWidgets

The widget deck at the foot of the sidebar: a stack of cards (Now Playing,
Software Update) with a stepper and gestures to move between them.
`BrowserSidebarWidgetHost` presents the deck for the whole application,
independent of the selected Space, and never in a private window.

## Goal

One deck both sidebars host, whose widgets are decided by what the build and
shell can render, not by Space or profile.

## Contents

| Path | What it is |
| --- | --- |
| `BrowserSidebarWidgetHost.swift` | Presents the deck in a sidebar |
| `Components/` | Deck, stepper, card, Now Playing and Software Update widgets |
| `Models/` | Deck gesture axis, software update details action |
| `Styles/` | Widget action button and quiet control styles |
| `Support/` | Widget artwork and deck style |

## Depends on

`CrestShared/Application/SidebarWidgets/` (registry, runtime, preferences,
software update phase, the `BrowserMediaSessionSnapshot` Now Playing reads),
`Sidebar/` (`BrowserSidebarMetrics`), `DesignSystem/`. Hosted by
`CrestMac/Features/Sidebar/` and `CrestMobile/Features/Sidebar/`; the Mac
update flow lives in `CrestMac/Features/SoftwareUpdates/`.

## Rules

- Which widgets show depends only on the platform, the shell's capabilities and each kind's instance policy, never the profile or Space (`CrestShared/Application/SidebarWidgets/BrowserSidebarWidgetRegistry.swift`, `visibleInstances`).
- Software update trust is a security decision worth a test; widget appearance is not (skill, "Tests").
- Widget styles reuse the design system's surfaces and tokens (skill, "Windows and UI").

## Read next

`CrestShared/Application/SidebarWidgets/`, then the hosting sidebar.
