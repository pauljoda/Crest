# CrestShared/Features/Chrome

The window chrome shared by both shells: the interaction capabilities every
shared view reads, the address content, the command palette (overlay or on
the Start Page), the Space pager, the sidebar resize handle and width, and
the chrome appearance and window layout persistence.

## Goal

One chrome contract that each shell fills with what it can do, so shared
components never branch on a device.

## Contents

| Path | What it is |
| --- | --- |
| `Models/` | `BrowserInteractionCapabilities`, chrome appearance and models, utility presentation, sidebar width transaction, command-surface morph and palette handoff |
| `BrowserAddressContent/` | The address text and its controls, long-press style and focus dismissal |
| `Components/BrowserCommandPalette/` | Crest's launcher: model, command registry, completion, result rows, provider chips |
| `Components/BrowserSpacePager/` | Paging between Spaces with a shared selection contract |
| `Components/BrowserSidebarResizeHandle/` | Dragging the sidebar width |
| `Components/BrowserChromeAppearancePersistence.swift` | Window corner and sidebar side at the scene boundary |
| `Services/` | Per-window layout persistence |
| `Support/` | Chrome layout, animation, accessibility, sidebar width preference, tab promotion identity |

## Depends on

`BrowserStore`, `BrowserSpaceAccessController`, the core's models through
`CrestShared/Infrastructure/Core/`, `CrestShared/Domain/` (runtime
assignments), `SearchProvider/`, `Settings/Models/` (device appearance),
`DesignSystem/`. Read by nearly every feature folder; hosted by the browser
roots in `CrestMac/Features/Browser/` and `CrestMobile/Features/Browser/`.

## Rules

- Shells supply `BrowserInteractionCapabilities`; shared views read capabilities, never a device or platform (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- Only appearance preferences, window geometry and transient presentation stay in Swift; the rest is core state (skill, "Architecture").
- An address the person types or chooses goes through the core's `Navigate` (`Documentation/ARCHITECTURE.md`, "Engine boundary").
- Small glyph buttons use `CrestChromeButtonStyle` (skill, "Windows and UI").

## Read next

`Documentation/ARCHITECTURE.md` ("Platform shape", "Windows on macOS"), then
the browser root of the shell being changed.
