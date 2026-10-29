# CrestEngines

Engine bindings that live outside the shared Swift tree. Today it holds one
engine, Chromium: the maintained fork's inputs and its Swift adapter. WebKit's
binding is Swift shared by both platforms and lives in
`CrestShared/Infrastructure/WebKit/` (`WebKitEngineBinding`), not here.

## Goal

Keep each engine behind the one engine contract, so the core's rules and the
shared UI never depend on which engine draws a page.

## Contents

| Folder | What it is |
| --- | --- |
| `Chromium/` | The maintained Chromium fork (recipe, patches, overlay, host header) and its Swift adapter ([CONTEXT](Chromium/CONTEXT.md)) |

## Depends on

The engine contract in `CrestContracts/include` (the C ABI and the generated
C++ engine codec `crest_engine_contract.h`); the engine port in `CrestShared/Infrastructure/Engines/`
(`BrowserPageEngine`, `BrowserEngineRegistration`). Consumed by the Mac
Chromium compositions in `project.yml`.

## Rules

- Bindings own page creation, loads, engine history, find, zoom, extensions and transfers; they report to the core and never decide browser rules (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Ownership").
- No Swift outside `CrestEngines` tests `CREST_CHROMIUM_HOST` (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Current state").
- Capability declarations in `BrowserEngineRegistration` describe what a binding really does; UI never gates on build flags (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Ownership").
- Place a new feature with the ownership decision guide (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Ownership decision guide").
- Engine-input changes need a maintainer-published engine (`AGENTS.md`, "Published Chromium engine").

## Read next

`Documentation/Architecture/EngineAbstractionCompletion.md`, then
`Chromium/CONTEXT.md`.
