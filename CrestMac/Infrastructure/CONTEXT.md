# Infrastructure

The Mac's adapters to AppKit, WebKit and macOS services: the page host and
engine events, Mac WebKit integration, the agent socket, keyboard shortcut
events, downloads, passkey access, web notifications, Now Playing, system
permissions and CloudKit entitlement. Shared adapters live in
`CrestShared/Infrastructure/`; these are their Mac sides.

## Goal

Every macOS system service sits behind one named adapter here, so shared code
never reaches the system directly; Mac features keep their own AppKit seams
(`Documentation/RepositoryGuardrails.md`, "Feature organization").

## Contents

| Path | What it is |
| --- | --- |
| `Pages/` | `BrowserPage`, `BrowserPagePool`, the engine adapter seam, web host view, title-bar guard and engine events ([CONTEXT](Pages/CONTEXT.md)) |
| `WebKit/` | The Mac WebKit page adapter, desktop web view, delegates, runtime store and content bridges ([CONTEXT](WebKit/CONTEXT.md)) |
| `Agents/` | The agent socket: listener, connection, peer code-signature check, approval questions |
| `BrowserShortcuts/` | `NSEvent` and hardware key code translation for keyboard shortcuts |
| `Downloads/` | Download directory, quarantine, Finder opening, and the feedback source (`Feedback/`) |
| `Engines/` | `BrowserEngineView` (the engine view seam as `NSView`) and the printing page engine |
| `BrowserPasskeyAccess/` | System passkey access and the Mac's (absent) password write-through |
| `BrowserHostedWebNotifications/` | Web notifications delivered through macOS notification center |
| `BrowserDefaultBrowser/` | Default-browser system integration |
| `MediaSessions/` | macOS Now Playing from the shared page media sessions |
| `SystemPermissions/` | System permission service and folder access |
| `PageActions/` | The page link clipboard (`Clipboard/`) |
| `CloudSync/` | The CloudKit sync service's entitlement check |
| `BrowserDialogPresenter.swift` | Which window a question attaches to as a sheet |

## Depends on

`CrestShared/Infrastructure/` (the shared ports and adapters these complete),
AppKit, WebKit, Security, UserNotifications and other system frameworks.
Consumed by `CrestMac/App/` and `CrestMac/Features/`.

## Rules

- Of the Swift source roots, only `CrestMac` may import AppKit, CoreServices and SecurityInterface (`Scripts/check-architecture.py`; `Documentation/RepositoryGuardrails.md`, "Architecture and Xcode 27 compatibility").
- Default-browser and passkey values and policies stay in shared Domain and their controllers in Application; AuthenticationServices, AppKit and Security bridges stay in Infrastructure (`Documentation/RepositoryGuardrails.md`, "Focused guard tests").
- A protocol needs two production implementations or a real system boundary (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- Import exemptions are exact entries with a reason in `Config/ArchitectureGuardrails.json`; an exemption is not precedent (`Documentation/RepositoryGuardrails.md`, "Architecture and Xcode 27 compatibility").
- Download risk, Keychain access and other security decisions are contracts worth a test (skill, "Tests").
- Only this Crest's own `crest-browser` helper, running as this user, may use the agent socket (`CrestMac/Infrastructure/Agents/BrowserAgentListener.swift`).

## Read next

`Documentation/ARCHITECTURE.md` ("Engine boundary", "Credentials and privacy"),
`CrestMac/Infrastructure/Pages/CONTEXT.md`, then the adapter being changed.
