# CrestMobile/Infrastructure

The iOS adapters the shared code reaches through platform seams: the WebKit
page and its per-scene store, the engine view type, and system services
(default browser, shared links, passkeys and Passwords, CloudKit entitlement,
downloads, clipboard). Most files resolve a `BrowserPlatform*` name that a
same-name Mac file also defines.

## Goal

Keep every UIKit, WebKit-on-iOS and system call behind a small seam, so shared
code compiles unchanged on both platforms.

## Contents

| Folder | What it is |
| --- | --- |
| `WebKit/` | `MobileBrowserPage` and its WebKit delegates, `MobileBrowserPageStore` and its registry, `MobileWebKit` (`BrowserPlatformWebKit`), user agent, dialogs, file and export pickers, link previews, link activation bridge, download risk confirmation, transient page leases |
| `Engines/` | `BrowserEngineView`, the engine view seam resolved to `UIView` |
| `BrowserDefaultBrowser/` | `BrowserPlatformDefaultBrowserSystem`: whether Crest is the default browser |
| `BrowserLinkSharing/` | `BrowserSharedLink`: the `crest://open` hand-off from the share extension |
| `BrowserPasskeyAccess/` | Passkey access and the system Passwords write-through |
| `CloudSync/` | The CloudKit container entitlement check for device and Simulator |
| `Downloads/` | The download directory and quarantine seams |
| `PageActions/Clipboard/` | `BrowserPageLinkClipboard` on `UIPasteboard` |

## Depends on

`CrestShared/Infrastructure/` (the engine port, the shared WebKit adapter,
sync transport and its CloudKit remote service, downloads, credentials),
WebKit, UIKit, AuthenticationServices. `BrowserLinkSharing/` is also compiled into
`CrestShareExtension` (`project.yml`). Consumed by `../Features/` and `../App/`.

## Rules

- iPhone and iPad run only WebKit; `MobileBrowserPage` is typed over WebKit by design (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Current state").
- Bindings report what the engine did and never decide browser rules; download risk, permissions and navigation are the core's answers (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Ownership").
- UIKit stays under `CrestMobile`; AppKit, CoreServices and SecurityInterface stay under `CrestMac` (`Documentation/RepositoryGuardrails.md`, "Architecture and Xcode 27 compatibility"; `Scripts/check-architecture.py`).
- Each scene owns its own page store and private browsing session (`Documentation/ARCHITECTURE.md`, "Scenes on iPhone and iPad").
- The share extension never compiles the core; keep `BrowserLinkSharing/` free of it (`project.yml`, the `CrestShareExtension` comment).
- A shared link carries the web link only and routes like any opened link (`CrestMobile/Infrastructure/BrowserLinkSharing/BrowserSharedLink.swift`, its doc comment).
- Do not enable the managed iOS default-browser entitlement until Apple approves it (`CONTRIBUTING.md`, "Change discipline").
- Keychain, sync codec, download risk and native input routing are contracts that earn a test (skill, "Tests").

## Read next

`Documentation/Architecture/EngineAbstractionCompletion.md` ("Ownership",
"How each engine behaves"), then `WebKit/MobileBrowserPageStore.swift`.
