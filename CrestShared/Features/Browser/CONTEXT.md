# CrestShared/Features/Browser

The pieces of the browser root that both shells assemble the same way: the
single-page detail surface, the root selection observer, the sidebar's
place (beside, floating, put away) and its toggle, the collapsed-sidebar
reveal control, the find bar and the window backdrop.

## Goal

Keep the root frame identical on both shells, so neither can compose a page,
sidebar or find bar differently.

## Contents

| Path | What it is |
| --- | --- |
| `Components/Sidebar/` | Sidebar page layout, layout reservation, surface layer, floating card background |
| `Components/BrowserFindBar/` | The find bar, its band and match status, `BrowserFindPort`, metrics |
| `Components/Backdrop/` | `BrowserWindowAtmosphere`, the Space-colored window backdrop |
| `Components/` (files) | Root detail surface, root selection observer, collapsed-sidebar reveal control |
| `Models/` | Sidebar presentation and the toggle action, target and handler |
| `Support/` | Root and collapsed-sidebar reveal metrics |

## Depends on

`Sidebar/` (toggle and page layout), `Chrome/`, `Spaces/` (banner
backdrop), `SplitView/` (page surface presentation), `DesignSystem/`, the
core's `SpaceModel` through `CrestShared/Infrastructure/Core/`, and find
matches from `CrestShared/Infrastructure/PageActions/`. Composed by
`CrestMac/Features/Browser/` and `CrestMobile/Features/Browser/`.

## Rules

- Platform roots compose scenes and host the engine's views; shared handlers own interaction state (`Documentation/ARCHITECTURE.md`, "Platform shape").
- Find, progress and zoom are page presentation, not core state (`Documentation/ARCHITECTURE.md`, "Engine boundary").
- Informational feedback uses the notice capsule, not alerts (skill, "Windows and UI").

## Read next

`Documentation/ARCHITECTURE.md` ("Windows on macOS", "Platform shape"), then
the platform `Browser/` root.
