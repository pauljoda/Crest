# CrestShared/Features

The feature UI both apps share, one folder per user purpose: the sidebar,
tabs, Spaces, settings, the window chrome, split view, transient pages and
the rest. Each folder holds the canonical component; `CrestMac/Features/` and
`CrestMobile/Features/` add only the platform seams around it.

## Goal

One implementation of each feature, adapting to its shell through
`BrowserInteractionCapabilities` (`Chrome/Models/`), never a device identity.

## Contents

| Folder | What it is |
| --- | --- |
| `Browser/` | The browser root's shared surfaces: page frame, collapsed-sidebar reveal, find bar, backdrop ([CONTEXT](Browser/CONTEXT.md)) |
| `BrowserShortcuts/` | Shortcut titles and glyphs, and their SwiftUI key equivalents |
| `Chrome/` | Window chrome: interaction capabilities, address content, command palette, Space pager, sidebar width ([CONTEXT](Chrome/CONTEXT.md)) |
| `Credentials/` | Password prompts on the page, the credential detail view, passkey access ([CONTEXT](Credentials/CONTEXT.md)) |
| `DataPortability/` | The import and export section and the exported file document ([CONTEXT](DataPortability/CONTEXT.md)) |
| `GettingStarted/` | The guided lessons and their practice window |
| `NativeTabs/` | The host and store for tabs whose content is a native view, not a website |
| `Navigation/` | The page shown when a navigation fails ([CONTEXT](Navigation/CONTEXT.md)) |
| `Onboarding/` | Setup pages, manual Space setup, session recovery ([CONTEXT](Onboarding/CONTEXT.md)) |
| `PageTranslation/` | Whole-page translation controls and host |
| `ReaderMode/` | Reader presentation and its errors |
| `SearchProvider/` | Search provider icons and labels |
| `Settings/` | The settings catalog, panes and sections both shells present ([CONTEXT](Settings/CONTEXT.md)) |
| `Sidebar/` | The Space sidebar: tab list, folders, splits, Space header and switcher, drag and drop ([CONTEXT](Sidebar/CONTEXT.md)) |
| `SidebarWidgets/` | The sidebar widget deck: now playing, software update ([CONTEXT](SidebarWidgets/CONTEXT.md)) |
| `SitePermissions/` | The page permission prompt and blocked-popup notice |
| `Spaces/` | Space branding, the Crest Studio, Space selectors ([CONTEXT](Spaces/CONTEXT.md)) |
| `SplitView/` | The split-view row of cards, dividers and drop targets ([CONTEXT](SplitView/CONTEXT.md)) |
| `StartPage/` | The surface a tab shows before it has a page |
| `Tabs/` | Tab presentation: favicons, status badges, pinned grid, folder colors ([CONTEXT](Tabs/CONTEXT.md)) |
| `TransientBrowsing/` | Peek and Quick Window cards, their action bar, promotion to a tab ([CONTEXT](TransientBrowsing/CONTEXT.md)) |
| `Utilities/` | A Space's Archive, History and Downloads lists ([CONTEXT](Utilities/CONTEXT.md)) |

## Depends on

`CrestShared/Application/` (stores, including `BrowserStore`),
`CrestShared/Domain/`, `CrestShared/DesignSystem/`, and the ports in
`CrestShared/Infrastructure/`. Consumed by `CrestMac/Features/`,
`CrestMobile/Features/` and the platform roots.

## Rules

- State changes go to the core as intents; views never mutate `BrowserStore.session` (skill, "Architecture").
- Shared views never call WebKit or Chromium APIs; they talk to the engine abstraction (skill, "Architecture"), whose ports are in `CrestShared/Infrastructure/Engines/`.
- Organize by user-visible feature; `Models`, `Components`, `Support`, `Services` are vocabulary, not required layers (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- A platform difference is a capability bit, shell input, optional action or accessory slot, in that order; never a forked component (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- Reuse `crestInteractiveSurface`, `CrestChromeButtonStyle` and the tokens (skill, "Windows and UI").
- Previews sit beside the component that owns editable UI and stay deterministic, with no live persistence, network or Keychain (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- No tests for appearance, copy, layout numbers or previews (skill, "Tests").

## Read next

`Documentation/ARCHITECTURE.md` ("Platform shape"), then the feature
folder's `CONTEXT.md` and its platform counterparts in `CrestMac/Features/`
and `CrestMobile/Features/`.
