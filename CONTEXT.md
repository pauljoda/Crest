# Crest

A native SwiftUI browser for Apple silicon. A portable .NET core owns browser
state and rules; Swift renders it; pages run in WebKit or Chromium behind
engine adapters. A Space is the privacy and organization boundary.

## Goal

One browser on Mac, iPhone and iPad whose rules live once, in the core, and
whose engines are interchangeable behind one adapter boundary.

## Contents

| Folder | What it is |
| --- | --- |
| `CrestCore/` | The portable .NET core: session, sync, access and policy rules ([CONTEXT](CrestCore/CONTEXT.md)) |
| `CrestContracts/` | The C ABI headers and native ABI test for the core library |
| `CrestShared/` | Swift shared by both platforms: domain, application, design system, features, infrastructure ([CONTEXT](CrestShared/CONTEXT.md)) |
| `CrestMac/` | The macOS app: shell, windows, Mac features, WebKit host ([CONTEXT](CrestMac/CONTEXT.md)) |
| `CrestMobile/` | The iPhone and iPad app: adaptive chrome and WebKit host |
| `CrestEngines/Chromium/` | The maintained Chromium fork and its Swift adapter ([CONTEXT](CrestEngines/Chromium/CONTEXT.md)) |
| `CrestNative/` | Native Apple glue for the core library |
| `CrestAgents/`, `CrestAgentHelper/` | The agent link protocol and the helper process for MCP clients |
| `CrestShareExtension/`, `CrestDockTilePlugin/` | System extensions |
| `CrestTests/`, `CrestMobileTests/`, `CrestTestFixtures/` | Swift tests and fixtures |
| `Config/` | Version, build configuration, the architecture exception register |
| `Scripts/` | Bootstrap, checks, validation, release and control-plane tooling |
| `Documentation/` | Architecture and contributor references ([index](Documentation/README.md)) |
| `HelpCenter/`, `Website/`, `Marketing/` | User help, the product site, App Store material |
| `ThirdParty/`, `ci_scripts/` | Vendored notices, Xcode Cloud scripts |

## Depends on

Xcode with the macOS and iOS 26.1 SDKs, XcodeGen, the .NET SDK in
`CrestCore/global.json`, Python 3.11+ (`CONTRIBUTING.md`, "Local setup").

## Rules

- The core owns shared state; Swift sends intents (skill, "Architecture").
- Shared code never calls WebKit or Chromium directly (skill, "Architecture").
- `project.yml` is authoritative; never hand-edit the Xcode project (`CONTRIBUTING.md`).
- App-code commits bump the patch version and add a release note (`AGENTS.md`).
- Engine-input changes need a maintainer-published engine (`AGENTS.md`).
- No task reports, screenshots or logs in the tree (`AGENTS.md`, "Test retention").

## Read next

[`ROUTING.md`](ROUTING.md) for the row that matches the change, then the
folder's `CONTEXT.md`.
