# CrestMobile/Features/Browser

The mobile browser root: `MobileBrowserRootView` and `MobileBrowserRootModel`,
which lay a window out as a compact (iPhone) or regular (iPad) browser, host
the live WebKit page view, and route commands, navigation, feedback and
presentation for one scene.

## Goal

One root per scene that composes the shared sidebar, page surface and chrome
into touch layouts, while the core and the page store own the state.

## Contents

| Path | What it is |
| --- | --- |
| `MobileBrowserRootView/MobileBrowserRootView.swift` | The root view a scene shows |
| `MobileBrowserRootView/Models/` | `MobileBrowserRootModel` and its commands, presentation, navigation state, compact and regular toggles, `MobileRegularWindowLayout`, `MobileBrowserFold`, tab swipe and page feedback values |
| `MobileBrowserRootView/Components/` | Compact and regular page surfaces and toolbars, the sidebar surface, the command palette layer, the URL-copy and page feedback capsule, history swipe border and controls, download risk confirmation, the utility fan |
| `MobileBrowserRootView/Components/MobileBrowserRootContent/` | The root content and its `Support/` extensions for commands, feedback, navigation and presentation |
| `MobileBrowserRootView/Components/MobileBrowserWebView/` | The UIKit host for the live page, its coordinator and the history swipe |
| `MobileBrowserRootView/Components/MobileTabSwipeStage/` | The tab swipe stage, slots and placeholders |
| `MobileBrowserRootView/Components/MobileSplitBubbleBar/` | The bubble bar for split pages |
| `MobileBrowserRootView/Support/` | `MobileBrowserRootLayout`, `PagePresentation+MobileBrowserPage` |
| `Components/` | `BrowserPlatformFindBarStyle` and `BrowserPlatformObservedTapModifier`, pairs of same-name Mac files |

## Depends on

`BrowserStore`, `MobileBrowserPageStore` (`../../Infrastructure/WebKit/`), the
shared features (`CrestShared/Features/Browser/`, `CrestShared/Features/Sidebar/`,
`CrestShared/Features/Chrome/`),
`../Sidebar/`, `../Chrome/`, `../TransientBrowsing/`, `../SplitView/`,
`../Commands/`, `../Settings/`. Created by
`CrestMobile/App/MobileBrowserWindowScene.swift`. Tests: `CrestMobileTests/MobileBrowserRootModelTests.swift`.

## Rules

- Layout follows width, not device: regular shares the persistent sidebar and page surface, compact uses compact navigation and sheets (`Documentation/ARCHITECTURE.md`, "Platform shape").
- Each scene owns its page store and live WebKit views; shared tab records never share a live page between scenes (`Documentation/ARCHITECTURE.md`, "Scenes on iPhone and iPad").
- Selection, tab and Space changes go through core intents; the root only renders and sends them (skill, "Architecture").
- Feedback such as "copied" is a notice capsule, never an alert or sheet; alerts and sheets only for a decision (skill, "Windows and UI").
- A popup window a page asks for opens as a tab beside the opener; iPhone and iPad have no Quick Window (`Documentation/LinkOpeningPolicy.md`, "Link opening").
- Keep root `body` and view builders small; split at meaningful subviews (`Documentation/RepositoryGuardrails.md`, "Feature organization").

## Read next

`Documentation/ARCHITECTURE.md` ("Platform shape", "Engine boundary"),
`../../Infrastructure/CONTEXT.md`, then `MobileBrowserRootModel.swift`.
