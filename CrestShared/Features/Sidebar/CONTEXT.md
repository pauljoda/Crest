# CrestShared/Features/Sidebar

The Space sidebar both shells show: the Space header and switcher, the
address field and navigation controls, pinned, saved and current tabs,
folders, split groups, selection and batch menus, and sidebar drag and drop.
`BrowserSidebar` owns Space selection, utility state and the clear-history
confirmation; each platform supplies its layout through `BrowserSidebarContext`.

## Goal

One sidebar whose rows, menus and reordering behave the same on every shell,
sized by `BrowserInteractionCapabilities` and the density preference.

## Contents

| Path | What it is |
| --- | --- |
| `BrowserSidebar.swift` | The shared sidebar owner |
| `BrowserSidebar/` | Its context, loaded content, clear-history dialog and preview fixture |
| `Components/` | Rows and sections: tab list and row, folder group, split group row, Space header and switcher, address field, navigation controls, drag, organization, selection and batch menus, icon customization |
| `Models/` | List items and context, interaction state, folder and split presentation |
| `Services/` | Tab, batch, selection, chrome and utility actions; the navigation and page-access ports |
| `Support/` | Metrics, density, folder layout and appearance, Space picker layout, `BrowserStore` and `SpaceModel` sidebar extensions |
| `Modifiers/` | The empty-space new-tab gesture |
| `Styles/` | The density font |

## Depends on

`BrowserStore` and the core read models, `Tabs/` (rows, favicons, pinned
grid), `Spaces/`, `Utilities/` (the Archive, History and Downloads lists),
`Chrome/`, `SplitView/` (split rows), `Settings/` (device appearance),
`BrowserSpaceAccessController`, `DesignSystem/`. Hosted by
`CrestMac/Features/Sidebar/` and `CrestMobile/Features/Sidebar/`, which
also place the `SidebarWidgets/` deck.

## Rules

- Tab, folder, split and Space edits are core intents, never direct session writes (skill, "Architecture").
- Each window and browsing mode owns a `BrowserSidebarInteractionState` for drags and measured reorder geometry (`Documentation/ARCHITECTURE.md`, "Platform shape").
- Touch, hover and drop-target sizing come from `BrowserInteractionCapabilities`, not the platform (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- Rows use `crestInteractiveSurface` and the tokens; no ad-hoc fills (skill, "Windows and UI").
- Name interaction thresholds and design metrics where they are owned (`Documentation/ARCHITECTURE.md`, "Platform shape").

## Read next

`Documentation/ARCHITECTURE.md` ("Platform shape", "Space isolation"),
`Documentation/NativeTabs.md` for native rows, then the platform sidebar
folder.
