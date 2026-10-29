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
| `CrestContracts/` | The C ABI headers (hand-written and generated) and the native ABI tests for the core library ([CONTEXT](CrestContracts/CONTEXT.md)) |
| `CrestShared/` | Swift shared by both platforms: domain, application, design system, features, infrastructure ([CONTEXT](CrestShared/CONTEXT.md)) |
| `CrestMac/` | The macOS app: shell, windows, Mac features, WebKit host ([CONTEXT](CrestMac/CONTEXT.md)) |
| `CrestMobile/` | The iPhone and iPad app: scenes, adaptive compact and regular chrome, mobile feature shells, the WebKit host and iOS adapters ([CONTEXT](CrestMobile/CONTEXT.md)) |
| `CrestEngines/` | Engine bindings outside the shared Swift tree: the maintained Chromium fork and its Swift adapter ([CONTEXT](CrestEngines/CONTEXT.md), [Chromium](CrestEngines/Chromium/CONTEXT.md)) |
| `CrestNative/` | Entitlements for the native-core targets and CloudKit review builds ([CONTEXT](CrestNative/CONTEXT.md)) |
| `CrestAgents/` | The agent link protocol and tool definitions shared by the Mac app and its helper ([CONTEXT](CrestAgents/CONTEXT.md)) |
| `CrestAgentHelper/` | `crest-browser`, the MCP helper agents run to reach Crest ([CONTEXT](CrestAgentHelper/CONTEXT.md)) |
| `CrestShareExtension/` | The iPhone and iPad share-sheet entry that hands links to Crest ([CONTEXT](CrestShareExtension/CONTEXT.md)) |
| `CrestDockTilePlugin/` | The macOS Dock tile plug-in that draws the chosen icon palette ([CONTEXT](CrestDockTilePlugin/CONTEXT.md)) |
| `CrestTests/` | macOS Swift tests for durable contracts, with support harnesses and fixtures ([CONTEXT](CrestTests/CONTEXT.md)) |
| `CrestMobileTests/` | iOS Swift tests for mobile-only adapter behavior ([CONTEXT](CrestMobileTests/CONTEXT.md)) |
| `CrestTestFixtures/` | Web pages and a counting local server for validation runs ([CONTEXT](CrestTestFixtures/CONTEXT.md)) |
| `Config/` | Version, architecture exception register, dependency register, export options, debugger settings ([CONTEXT](Config/CONTEXT.md)) |
| `Scripts/` | Bootstrap, checks, validation, versioning, release and control-plane tooling ([CONTEXT](Scripts/CONTEXT.md)) |
| `Documentation/` | Architecture and contributor references ([CONTEXT](Documentation/CONTEXT.md), [index](Documentation/README.md)) |
| `HelpCenter/` | Crest Help, the Docusaurus user guides ([CONTEXT](HelpCenter/CONTEXT.md)) |
| `Website/` | The static product site; `guides/` is the built Help Center ([CONTEXT](Website/CONTEXT.md)) |
| `Marketing/` | App Store material |
| `ThirdParty/` | Retained license notices for redistributed dependencies ([CONTEXT](ThirdParty/CONTEXT.md)) |
| `ci_scripts/` | Xcode Cloud archive guard hooks ([CONTEXT](ci_scripts/CONTEXT.md)) |

## Depends on

Xcode with SDKs supporting the macOS 26.1 and iOS 26.1 deployment targets,
XcodeGen, the .NET SDK in `CrestCore/global.json`, Python 3.11+ for the
Chromium and release tools, ripgrep for the script tests, and Node.js 20+ for
`HelpCenter/` (`CONTRIBUTING.md`, "Local setup").

## Rules

- The core owns shared state; Swift sends intents (skill, "Architecture").
- Shared code never calls WebKit or Chromium directly (skill, "Architecture").
- `project.yml` is authoritative; edit it and run `xcodegen generate`, never hand-edit the Xcode project (`CONTRIBUTING.md`, "Local setup"; skill, "Pull request").
- App-code commits bump the patch version and add a release note (`AGENTS.md`, "Versioning completed work", "Explicit release notes").
- Engine-input changes need a maintainer-published engine (`AGENTS.md`, "Published Chromium engine").
- No task reports, screenshots or logs in the tree (`AGENTS.md`, "Test retention and cleanup").

## Read next

[`ROUTING.md`](ROUTING.md) for the row that matches the change, then the
folder's `CONTEXT.md`.
