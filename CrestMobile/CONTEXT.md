# CrestMobile

The iPhone and iPad app: the scene that hosts a window, the adaptive compact
and regular chrome, mobile presentation for each feature, the UIKit and system
adapters, and the WebKit page host. It composes `CrestShared`; iPhone and iPad
run only WebKit.

## Goal

One touch-first browser over the same core, UI and sync records as the Mac,
whose platform code is only the seams UIKit and iOS require.

## Contents

| Folder | What it is |
| --- | --- |
| `App/` | `CrestMobileApp`, the `WindowGroup` keyed by `MobileWindowRequest`, `MobileBrowserWindowScene` and its models |
| `Features/` | Mobile presentation by user purpose: Browser, Sidebar, Settings, Chrome, Tabs, Spaces, SplitView, TransientBrowsing, ... ([CONTEXT](Features/CONTEXT.md)) |
| `Infrastructure/` | The WebKit page host and store, the engine view seam, default browser, link sharing, passkeys, CloudKit, downloads, clipboard ([CONTEXT](Infrastructure/CONTEXT.md)) |
| `DesignSystem/` | Mobile-only colors, metrics and modifiers (`CrestPlatform*`) |
| `PreviewSupport/` | `MobileBrowserPreviewFixture` for mobile previews |
| `Configuration/` | `CrestMobile-Info.plist` and `CrestMobile.entitlements` |
| `Resources/` | The mobile asset catalog (accent color) |

## Depends on

`CrestShared`, `CrestCore` (through CrestShared and the `CrestCoreABI`
framework), WebKit. Built by the `CrestMobile` and `CrestMobileNativeCore`
targets in `project.yml`; `CrestShareExtension` also compiles
`Infrastructure/BrowserLinkSharing/`. Tests: `CrestMobileTests/`. UIKit is
allowed only in this tree (`Scripts/check-architecture.py`).

## Rules

- Never mutate `BrowserStore.session` or other shared state; send a core intent (skill, "Architecture").
- A platform file exists only for a genuine seam; never fork a shared component's behavior (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- Platform differences come from `BrowserInteractionCapabilities`, not a device identity (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- Each scene owns its own page store, live WebKit views and private session; shared tab records never share a live page (`Documentation/ARCHITECTURE.md`, "Scenes on iPhone and iPad").
- The Mac window coordinator, live-page handoff and tab tear-off are Mac-only (`Documentation/ARCHITECTURE.md`, "Scenes on iPhone and iPad").
- Do not enable the managed iOS default-browser entitlement until Apple approves it (`CONTRIBUTING.md`, "Change discipline").
- Informational feedback is a notice, never an alert or sheet (skill, "Windows and UI").
- Validation launches use `CREST_ISOLATED_SESSION=1` (`Documentation/RepositoryGuardrails.md`, "Isolated validation sessions").
- Visual changes are checked in the running app or Simulator and shown in the pull request (skill, "Verification and reporting"); appearance is never tested (skill, "Tests").

## Read next

`Documentation/ARCHITECTURE.md` ("Scenes on iPhone and iPad", "Platform
shape"), `../CrestShared/CONTEXT.md`, then the feature folder.
