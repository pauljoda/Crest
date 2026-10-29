# Application

Cross-platform coordination: the observable stores, controllers and sessions
that sit between the features and the core. Each one sends core intents,
follows the read model, and drives a workflow (setup, sync, prompts,
credentials, Peek) through ports that `Infrastructure/` and the platform
trees implement.

## Goal

One workflow implementation per browser area, testable without a UI or
system framework, holding no browser state the core owns.

## Contents

| Path | What it is |
| --- | --- |
| `BrowserStore/` | The per-window facade over the core: what a window shows and the intents it sends ([CONTEXT](BrowserStore/CONTEXT.md)) |
| `BrowserAppPreferences/` | The core's app-wide behavior preferences as settings bind them |
| `BrowserAuthentication/` | Answering a server's sign-in challenge through the core |
| `BrowserCloudSync/` | The iCloud sync controller: performs each step the core decides |
| `BrowserDefaultBrowser/` | Whether Crest opens links, and asking to become the default |
| `BrowserFavicon/` | Favicon capture sessions over a document adapter |
| `BrowserFaviconPalette/` | Loading favicon palettes |
| `BrowserFilterLists/` | Each Space's content-blocking choice and its updates |
| `BrowserLaunch/` | Parsed launch flags and the launch decision |
| `BrowserLinkPreferences/` | The platform side of link-route preferences |
| `BrowserNavigation/` | External-scheme hand-off and server-trust overrides |
| `BrowserObservation/` | `BrowserStoreFirstObservable`: store a value before announcing it |
| `BrowserOnboarding/` | The setup and welcome workflow |
| `BrowserPasskeyAccess/` | When passkey access may be requested |
| `BrowserPrompts/` | Presenting the questions the core asks: script dialogs, system consent, dismissal |
| `BrowserSearch/` | This device's search-provider catalog |
| `BrowserShortcuts/` | The platform side of shortcut bindings and their settings |
| `BrowserSitePermissions/` | Site permission choices and one page's pending requests |
| `BrowserSpaceAccess/` | The app's Space access controller (locked Spaces, device authentication) |
| `BrowserSpaceDeletion/` | Erasing what the platform and every engine keep for a deleted Space |
| `BrowserTransientBrowsing/` | Peek requests and link-pull lifetimes |
| `Credentials/` | Credential suggestions, save prompts, strong passwords, capture |
| `MediaSessions/` | Media sessions, Now Playing actions and the audio spectrum feed |
| `ReaderMode/` | Reader sessions over a document adapter |
| `SidebarWidgets/` | The sidebar widget deck: presentation, actions, runtime, visibility |
| `BrowserWindowLayouts.swift`, `BrowserWindowStateStore.swift` | Each window's sidebar layout on this device |
| `ProductIdentity.swift` | The product name, bundle identifier and storage directory name |

## Depends on

`Domain/` and the core's read model and intents (`Infrastructure/Core/`).
Consumed by `Features/`, the platform trees and the engine adapters, which
also supply the ports declared here.

## Rules

- Application imports only Foundation, Observation, Dispatch and Synchronization, so no SwiftUI, AppKit, UIKit or WebKit (`Scripts/check-architecture.py`, `LAYER_IMPORT_POLICIES`; `Documentation/RepositoryGuardrails.md`, "Architecture and Xcode 27 compatibility").
- Never mutate shared state from Swift; send a core intent and apply the change it returns (skill, "Architecture").
- Default-browser and passkey workflow controllers stay here; their system bridges stay in Infrastructure (`Documentation/RepositoryGuardrails.md`, "Focused guard tests").
- No `ObservableObject` or `@Published` (`Documentation/RepositoryGuardrails.md`, "Architecture and Xcode 27 compatibility"); store before announcing (`BrowserStoreFirstObservable`, `Documentation/Architecture/ControlPlane.md`, "The read model").
- A protocol needs two production implementations or a real system boundary (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- Launch flags are parsed by `BrowserLaunchEnvironment` and only read from the process in Infrastructure (`Documentation/RepositoryGuardrails.md`, "Focused guard tests").

## Read next

`Documentation/Architecture/ControlPlane.md` ("The read model", "What stays
in Swift"), then `BrowserStore/CONTEXT.md` or the area folder being changed.
