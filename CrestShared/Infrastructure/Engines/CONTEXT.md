# Engines

The engine port: the engine-neutral types shared code uses to host and drive
pages on WebKit or Chromium. An `EngineBinding` builds an engine's page when
the core asks; `EnginePage` and `EnginePages` are the platform's direct path
to a page's engine; `EnginePageReporter` tells the core what a page shows;
`BrowserEngineRegistration` declares which engine a composition offers and
what it can do.

## Goal

Shared Swift hosts any engine through one port, so adding or swapping an
engine touches its binding and registration only.

## Contents

| Path | What it is |
| --- | --- |
| `EngineBinding.swift`, `NativeEngineBinding.swift` | A browsing engine the core hosts pages on; one whose binding is written outside Swift, as Chromium's is |
| `EnginePage.swift`, `EnginePages.swift`, `NativeEnginePages.swift`, `Engines.swift` | The platform's direct path to one page's engine and to all of an engine's pages; what a binding built for a page |
| `EnginePage+Agent.swift`, `EnginePageAgentWaits.swift`, `EnginePageInput.swift` | What an allowed agent asks of a page: scripts, input and what they wait for |
| `EnginePageReporter.swift` | Reports a page's state, navigations and events to the core |
| `CorePage.swift` | A page the core opened for this platform |
| `BrowserPageEngine.swift`, `BrowserPageContentScripting.swift` | The native page port views use, and content-bridge scripting in an isolated world |
| `BrowserEngineRegistration.swift`, `BrowserAdapterRegistration.swift`, `BrowserEngineImplementation.swift` | The integrations a composition can select and what each declares it supports |
| `BrowserEngineRegistration+Composition.swift` | `current` for the WebKit compositions; the Chromium framework excludes it and supplies its own |
| `BrowserEngineInteractionState.swift`, `BrowserEngineProfileRemoving.swift` | Opaque engine interaction state; removing a profile's engine stores |
| `Commands/` | Which engine hosts a page as commands create, adopt and close it |
| `Presentations/` | Engine presentations (navigation committed or failed, view ready, input delivered, find, capture, export, script results) handed to the page they concern |

## Depends on

`Core/` (engine commands, presentations, reports), `Domain/`, and
`CrestCoreABI` for the native engine binding (`NativeEngineBinding`). Implemented
by `../WebKit/` and the Chromium adapter
(`CrestEngines/Chromium/Apple/`). Consumed by the platform page hosts and
the features.

## Rules

- Shared code never calls WebKit or Chromium APIs; it talks to this port (skill, "Architecture").
- No engine types or engine `#if` flags outside engine code; UI gates on what the core offers, never on build flags (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Ownership").
- Capabilities declared in `BrowserEngineRegistration` describe what the binding really does; a missing capability has explicit product behavior (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Ownership"; `Documentation/Architecture/ControlPlane.md`, "Registration, capabilities and offering").
- Registration is local to the process, selected by its composition and never saved or synced (`Documentation/Architecture/ControlPlane.md`, "Registration, capabilities and offering"; doc comment in `BrowserEngineRegistration+Composition.swift`, which `project.yml` excludes from the Chromium framework).
- A page another page opens stays on its opener's engine (skill, "Architecture").
- A change to the engine command or event contract regenerates `crest_engine_contract.h`, which changes the Chromium engine key (`Scripts/control-plane/chromium_engine.py`; `AGENTS.md`, "Published Chromium engine").

## Read next

`Documentation/Architecture/EngineAbstractionCompletion.md` ("Ownership
decision guide"), `Documentation/Architecture/ControlPlane.md` ("Engines"),
then `../WebKit/CONTEXT.md` or `CrestEngines/Chromium/CONTEXT.md`.
