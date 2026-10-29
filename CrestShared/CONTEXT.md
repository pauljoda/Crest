# CrestShared

Swift shared by the Mac and mobile apps: value types and policies, the stores
that coordinate them, the design system, the feature UI, and the adapters to
the core and the engines. UI components are canonical here; platform trees add
only genuine platform seams.

## Goal

One implementation of every feature, reading what its environment can do from
`BrowserInteractionCapabilities` rather than from a device identity.

## Contents

| Folder | What it is |
| --- | --- |
| `Domain/` | Value types, policies and state transitions per browser concept; imports Foundation only ([CONTEXT](Domain/CONTEXT.md)) |
| `Application/` | Cross-platform coordination and stores, including `BrowserStore`; no UI or system frameworks ([CONTEXT](Application/CONTEXT.md)) |
| `DesignSystem/` | Tokens, components, modifiers, accessibility and animation; search here before writing a control or fill ([CONTEXT](DesignSystem/CONTEXT.md)) |
| `Features/` | Shared feature UI by user purpose: Browser, BrowserShortcuts, Chrome, Credentials, DataPortability, GettingStarted, NativeTabs, Navigation, Onboarding, PageTranslation, ReaderMode, SearchProvider, Settings, Sidebar, SidebarWidgets, SitePermissions, Spaces, SplitView, StartPage, Tabs, TransientBrowsing, Utilities ([CONTEXT](Features/CONTEXT.md)) |
| `Infrastructure/` | Adapters: Core (the Swift side of the core; `Core/Generated/` is written by the contract generator), Engines (the `BrowserPageEngine` port), WebKit (the shared WebKit adapter), Authentication, ControlPlane, Credentials, Diagnostics, Downloads, Favicons, Geolocation, HostedWebNotifications, Launch, Links, MediaSessions, PageActions, Pages, Popups, Preferences, Session, SitePermissions, Sync, Tabs ([CONTEXT](Infrastructure/CONTEXT.md)) |
| `Resources/` | Localizations (`Localizable.xcstrings`), privacy manifest, asset catalogs, app icon, emoji and SF Symbol catalogs ([CONTEXT](Resources/CONTEXT.md)) |
| `PreviewSupport/` | Shared preview fixtures |

## Depends on

`CrestCore` through `Infrastructure/Core/` (`CrestCoreABI`). Not a module of
its own: `project.yml` compiles it into each app target beside `CrestMac` or
`CrestMobile`, and into the Chromium host framework beside
`CrestEngines/Chromium/Apple/`.

## Rules

- Never change shared state from Swift; send a core intent (skill, "Architecture").
- Layer imports are checked by `Scripts/check-architecture.py`; SwiftUI stays out of Infrastructure (`Documentation/RepositoryGuardrails.md`, "Architecture and Xcode 27 compatibility").
- No `ObservableObject`, `@Published` or `AnyView` in production code (`Documentation/RepositoryGuardrails.md`, "Architecture and Xcode 27 compatibility").
- Reuse `crestInteractiveSurface`, `CrestChromeButtonStyle` and the tokens; no ad-hoc fills (skill, "Windows and UI").
- Never hand-edit `Infrastructure/Core/Generated/`; change the contract and regenerate (`Documentation/Architecture/ControlPlane.md`, "The typed contract").
- A regenerated `Localizable.xcstrings` belongs to the change that caused it (`AGENTS.md`, "Generated localization catalog").
- Feature organization and preview rules: `Documentation/RepositoryGuardrails.md`, "Feature organization".

## Read next

`Documentation/ARCHITECTURE.md` ("Engine boundary", "Platform shape"), then
the feature folder being changed.
