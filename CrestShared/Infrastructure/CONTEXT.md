# Infrastructure

The shared adapters: the Swift side of the core, the engine port and the
WebKit binding, and the bridges to system services (Keychain, CloudKit,
AuthenticationServices, Core Location, Translation). Each
folder implements the ports `Application/` declares, or translates between a
system or engine type and a core contract.

## Goal

Keep every framework, engine and wire detail behind one adapter, so
Application and the features see only typed values, core intents and the
read model.

## Contents

| Folder | What it is |
| --- | --- |
| `Core/` | The Swift side of the core: `CrestCore`, the `CoreState` read model, changes, seeds; `Generated/` is written by the contract generator ([CONTEXT](Core/CONTEXT.md)) |
| `Engines/` | The engine port: `BrowserPageEngine`, `EngineBinding`, engine registration, `EnginePageReporter` ([CONTEXT](Engines/CONTEXT.md)) |
| `WebKit/` | WebKit's binding, shared by Mac, iPhone and iPad ([CONTEXT](WebKit/CONTEXT.md)) |
| `ControlPlane/` | Platform answers to core questions and URL, identifier and capacity translations on core contract types |
| `Authentication/` | Foundation's HTTP authentication challenges translated to and from the core's |
| `Credentials/` | The credential session and content bridge for both engines, Keychain storage (`Keychain/`) and passkeys (`Passkeys/`) |
| `Diagnostics/` | `DiagnosticLog`, the unified-log categories |
| `Downloads/` | The download center, destinations, quarantine, risk facts and transfers |
| `Favicons/` | Favicon stores and public fallback loading |
| `Geolocation/` | The Core Location service |
| `HostedWebNotifications/` | The port that delivers web notifications through the system |
| `Launch/` | Application launch, process launch flags, store composition, persistence flush at quit |
| `Links/` | Link and split hosts a page needs from its tab owner |
| `MediaSessions/` | How a page's Media Session state and commands cross to Crest |
| `PageActions/` | Page operations: find, zoom, reload, export, translation, Reader bridge, developer panel, back/forward items |
| `Pages/` | `BrowserPageHost`, `BrowserPageOwner`, `BrowserTabRuntime`, page reconciliation, tab state, memory pressure |
| `Popups/` | Popup scheme routing and blocked-popup decisions |
| `Preferences/` | Reading preferences older releases kept in defaults |
| `Session/` | Session recovery and the pre-core session defaults |
| `SitePermissions/` | Keeping a page's engine in step with per-Space permissions; system consent |
| `Sync/` | The CloudKit transport (`CloudKit/`) and sync preferences |
| `Tabs/` | The on-disk archive of each tab's engine history |

## Depends on

`Domain/`, `Application/` ports, the core through `CrestCoreABI`
(`CrestContracts/include/module.modulemap`), and system frameworks. Consumed
by the platform trees, the features and the Chromium adapter.

## Rules

- No SwiftUI in shared Infrastructure; AppKit, CoreServices and SecurityInterface stay in `CrestMac`, UIKit in `CrestMobile` (`Documentation/RepositoryGuardrails.md`, "Architecture and Xcode 27 compatibility").
- Default-browser and passkey system bridges (AuthenticationServices, Security) belong in shared or platform Infrastructure, not in Domain or Application (`Documentation/RepositoryGuardrails.md`, "Focused guard tests").
- Launch flags are read from the process only by the Infrastructure adapter (`Documentation/RepositoryGuardrails.md`, "Focused guard tests").
- Shared code talks to the engine port, never to WebKit or Chromium APIs (skill, "Architecture"); engine types stay in the engine bindings (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Ownership").
- Bindings report events and never decide browser rules (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Ownership").
- Never hand-edit `Core/Generated/`; change the contract and regenerate (`Documentation/Architecture/ControlPlane.md`, "The typed contract").
- Every exemption is listed in `Config/ArchitectureGuardrails.json`; an exemption is not precedent (`Documentation/RepositoryGuardrails.md`, "Architecture and Xcode 27 compatibility").

## Read next

`Documentation/Architecture/ControlPlane.md` ("Engines", "Page lifecycle"),
`Documentation/Architecture/EngineAbstractionCompletion.md` ("Ownership"),
then the child folder's `CONTEXT.md` or code.
