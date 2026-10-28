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
| `Domain/` | Value types, policies and state transitions per browser concept; imports Foundation only |
| `Application/` | Cross-platform coordination and stores, including `BrowserStore`; Foundation, Observation and Dispatch only |
| `DesignSystem/` | Tokens, components, modifiers, accessibility and animation; search here before writing a control or fill |
| `Features/` | Shared feature UI by user purpose: Sidebar, Tabs, Spaces, Settings, Chrome, Credentials, SplitView, ... |
| `Infrastructure/Core/` | The Swift side of the core: read models, changes, commands; `Generated/` is written by the contract generator |
| `Infrastructure/Engines/` | The engine port: `BrowserPageEngine`, engine registration, page reporting |
| `Infrastructure/WebKit/` | The shared WebKit adapter |
| `Infrastructure/` (others) | Keychain credentials, sync transport, downloads, favicons, launch, page actions, ... |
| `Resources/` | Localizations (`Localizable.xcstrings`), privacy manifest, asset catalogs, app icon |
| `PreviewSupport/` | Shared preview fixtures |

## Depends on

`CrestCore` through `Infrastructure/Core/`. Consumed by `CrestMac`,
`CrestMobile` and the Chromium adapter.

## Rules

- Never mutate `BrowserStore.session` or other shared state from Swift; send a core intent (skill, "Architecture").
- Layer imports are checked by `Scripts/check-architecture.py`; SwiftUI stays out of Infrastructure (`Documentation/RepositoryGuardrails.md`).
- No `ObservableObject`, `@Published` or `AnyView` in production code (same).
- Reuse `crestInteractiveSurface`, `CrestChromeButtonStyle` and the tokens; no ad-hoc fills (skill, "Windows and UI").
- Never hand-edit `Infrastructure/Core/Generated/`; regenerate from CrestCore.
- A regenerated `Localizable.xcstrings` belongs to the change that caused it (`AGENTS.md`).
- Feature organization and preview rules: `Documentation/RepositoryGuardrails.md`, "Feature organization".

## Read next

`Documentation/ARCHITECTURE.md` ("Engine boundary", "Platform shape"), then
the feature folder being changed.
