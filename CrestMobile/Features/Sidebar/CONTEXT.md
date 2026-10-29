# CrestMobile/Features/Sidebar

The touch shell around the shared sidebar: `MobileBrowserSidebarContent`, the
horizontal Space pager whose pages each show one Space, the Space action
buttons, and the UIKit drag, reorder and gesture seams the shared sidebar
reads through its ports.

## Goal

The shared sidebar's rows, menus and reorder rules on iPhone and iPad, with
only touch presentation and UIKit gestures added here.

## Contents

| Path | What it is |
| --- | --- |
| `MobileBrowserSidebar/Components/MobileBrowserSidebarContent/` | The sidebar content: top and bottom chrome, layout, the Space pager, Space surface and content |
| `MobileBrowserSidebar/Components/MobileSpaceActions/` | The Space action buttons: archive, downloads, private browsing, settings, utility badge |
| `MobileBrowserSidebar/Components/Tabs/` | The tab transition source modifier |
| `MobileBrowserSidebar/Components/` (files) | `MobileBrowserSpacePage`, sidebar presentation, tab-list scroll, the compact new-tab prompt, drag release gesture, vertical widget page control |
| `MobileBrowserSidebar/Models/` | Sidebar and presentation models, the utility presentation style |
| `MobileBrowserSidebar/Services/` | `MobileSavedLocationRestoreAction` |
| `MobileBrowserSidebar/Support/` | The drag release coordinator and the sidebar preview fixture |
| `Components/BrowserSidebarDrag/` | UIKit drag and drop: `BrowserMobileDragRouter`, drag session, drag sources, reorder drop target and feed |
| `Components/BrowserSidebarRow/` | Row auxiliary click and tab promotion source modifiers |
| `Components/BrowserSidebarNavigationControls/` | The navigation history menu modifier |
| `Components/BrowserSpaceSwitcher/` | `PlatformSpacePickerPresentation`, the touch-tracking highlight of the shared Space picker |
| `Components/BrowserIconCustomization/` | The emoji entry field and variant modifier |
| `Components/BrowserPlatformTabSelectionTarget.swift` | The tab selection target |
| `Support/` | Bindings of the shared sidebar's ports to the page store: tab actions, navigation port, utility coordinator |

The `BrowserPlatform*` and `PlatformSpacePickerPresentation` files pair
same-name files in `CrestMac/Features/Sidebar/`.

## Depends on

`CrestShared/Features/Sidebar/` (`BrowserSidebar`, its actions and ports, the
shared reorder state), `BrowserStore`, `MobileBrowserPageStore`. Consumed by
`../Browser/` (`MobileBrowserSidebarSurface`). Tests:
`CrestMobileTests/MobileBrowserSidebarReorderPolicyTests.swift`,
`BrowserMobileDragSourceTests.swift`.

## Rules

- Shared handlers own interaction state, source validation, cancellation and commitment; UIKit code here only translates native input (`Documentation/ARCHITECTURE.md`, "Platform shape").
- Each window and browsing mode owns a `BrowserSidebarInteractionState` for drag sessions and reorder geometry (`Documentation/ARCHITECTURE.md`, "Platform shape").
- Tab, folder and Space moves go through core intents (skill, "Architecture").
- Never fork a shared sidebar component; add a capability bit, shell input, optional action or accessory slot (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- Interactive rows and buttons use `crestInteractiveSurface` and `CrestChromeButtonStyle` (skill, "Windows and UI").

## Read next

`CrestShared/Features/Sidebar/`, then `Documentation/ARCHITECTURE.md`
("Platform shape").
