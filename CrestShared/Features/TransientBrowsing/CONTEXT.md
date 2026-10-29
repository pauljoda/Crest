# CrestShared/Features/TransientBrowsing

The shared UI for transient pages: Peek and Quick Window cards over the
browser, their scrim and card stack, the Peek action bar with its
destination menu, the unavailable-Space view, the leases that hold a
transient page, and promotion of that page into a tab.

## Goal

One transient surface, named per shell
(`Models/BrowserTransientModels.swift`), that a person can keep as a tab or
drop without a new window appearing.

## Contents

| Path | What it is |
| --- | --- |
| `Components/BrowserTransientSurface/` | The transient surface, card stack and motion |
| `Components/BrowserPeekActionBar/` | Close and destination controls for a Peek |
| `Components/` (files) | Scrim, page card, overlay content, unavailable-Space view |
| `Models/` | The words a transient overlay uses and its presentation state |
| `Services/` | `BrowserTransientPagePromotion` and the Quick Window preferences |
| `Support/` | Card layout and arrangement, lease holder and disposition, `BrowserStore` transient Spaces |

## Depends on

`BrowserStore`, `BrowserSpaceAccessController`, the core's `SpaceModel`
through `CrestShared/Infrastructure/Core/`, the engine port's `CorePage`
(`CrestShared/Infrastructure/Engines/`), `CrestShared/Domain/` (runtime
assignments), `Spaces/` (Space identity), `DesignSystem/`. Hosted by
`CrestMac/Features/TransientBrowsing/`, `CrestMac/Features/QuickWindow/` and
`CrestMobile/Features/TransientBrowsing/`, whose Peek and Quick Window
coordination is `CrestShared/Application/BrowserTransientBrowsing/`.

## Rules

- Never create a window the person did not ask for; on the Mac a popup window opens as a Quick Window in the opener's engine and Space, on iPhone and iPad as a tab (`Documentation/LinkOpeningPolicy.md`, "Link opening"; skill, "Windows and UI").
- Which link opens a Peek, a Quick Window or a tab is the gesture table in `Documentation/LinkOpeningPolicy.md`, "Link opening".
- Quick Window and Peek borrow the selected Space's session boundary (`Documentation/ARCHITECTURE.md`, "Space isolation").
- Keeping a page as a tab is a core decision; the adapter moves it when the platform can (`CrestShared/Features/TransientBrowsing/Services/BrowserTransientPagePromotion.swift`).

## Read next

`Documentation/LinkOpeningPolicy.md`, then `CrestMac/Features/QuickWindow/`
or the mobile transient folder.
