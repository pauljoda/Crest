# CrestMobile/Features

Mobile presentation by user purpose. Each folder holds the iPhone and iPad
shell around a shared feature in `CrestShared/Features`, or the seams UIKit
needs: touch gestures, drag sessions, compact and regular layouts, sheets, and
`BrowserPlatform*` files that pair a same-name Mac file.

## Goal

Present each shared feature natively on touch without a second copy of its
content, actions or rules.

## Contents

| Folder | What it is |
| --- | --- |
| `Browser/` | `MobileBrowserRootView` and its model: compact and regular layouts, page surfaces, tab swipe, history swipe, split bubbles ([CONTEXT](Browser/CONTEXT.md)) |
| `Sidebar/` | `MobileBrowserSidebar`, the Space pager, Space actions, UIKit drag and reorder, row and Space-switcher seams ([CONTEXT](Sidebar/CONTEXT.md)) |
| `Settings/` | `MobileBrowserSettingsView`, compact and regular settings layouts, Space settings, link route editor, Forge step bar ([CONTEXT](Settings/CONTEXT.md)) |
| `Chrome/` | `MobileCompactAddressBar`, page actions, the Space pager, the command palette field, the history menu |
| `Commands/` | `MobileBrowserCommand` and its controller: what each palette or hardware-keyboard command does on iPhone and iPad |
| `Tabs/` | The pinned tab grid, the tab equalizer, the getting-started icon |
| `Spaces/` | Space color well, inline name dismissal, the `BrandColor` platform color |
| `SplitView/` | Split cards, column resize, focus tap and drop feed |
| `TransientBrowsing/` | `MobileBrowserTransientOverlay`: peek and Quick Window requests as cards over the page |
| `NativeTabs/` | The settings and getting-started tab adapters for native tabs |
| `Onboarding/` | `MobileBrowserOnboardingView`: pages, layout, progress |
| `Credentials/` | `MobilePasswordSettingsView`, the sheet around the shared password pane, and the credential clipboard |
| `Archive/`, `History/`, `Downloads/` | Mobile list screens for archived tabs, history and downloads |
| `Utilities/` | `BrowserPlatformUtilityFilterMenuStyle` |

## Depends on

`CrestShared/Features` (the canonical components), `CrestShared/DesignSystem`,
`BrowserStore`, and `CrestMobile/Infrastructure/WebKit/` (`MobileBrowserPageStore`).
Consumed by `CrestMobile/App/MobileBrowserWindowScene.swift`.

## Rules

- UI components are canonical in `CrestShared`; a file here exists only for a genuine platform seam, and a divergence uses a capability bit, shell input, optional action or accessory slot, in that order (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- Organize by user-visible feature; `Components`, `Models`, `Services`, `Support` are vocabulary, not layers (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- Shared state changes go through core intents (skill, "Architecture").
- Reuse `crestInteractiveSurface`, `CrestChromeButtonStyle` and the tokens; no ad-hoc fills (skill, "Windows and UI").
- Strings go through `String(localized:)`; a regenerated `CrestShared/Resources/Localizable.xcstrings` belongs to the change (skill, "Writing"; `AGENTS.md`, "Generated localization catalog").
- Previews sit beside the components that own editable UI, deterministic and inside `#if DEBUG` (`Documentation/RepositoryGuardrails.md`, "Feature organization").

## Read next

The shared folder of the same name in `CrestShared/Features/`, then
`Documentation/ARCHITECTURE.md` ("Platform shape").
