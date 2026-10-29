# Core

The Swift side of the portable core. `CrestCore` is the app's one connection
to the core's typed API: `send` runs an intent and applies the changes it
caused before returning, `query` reads, and a wake drains changes the core
started itself. `CoreState` is the observable read model those changes
update, one object per workspace, Space, tab, folder, window and page.

## Goal

Swift reads browser state only from `CoreState` and changes it only through
intents, with the wire format generated from the C# contract records.

## Contents

| Path | What it is |
| --- | --- |
| `Generated/` | `CoreContracts.generated.swift` and `CoreCodec.generated.swift`: contract types and the wire codec, written by `CrestCore/tools/CrestCore.Generator` |
| `Changes/` | One `<Change>+CoreState.swift` per change, in one folder per area (`Access`, `Agents`, `Closing`, `DataDeletion`, `Downloads`, `Engines`, `Links`, `Pages`, `Prompts`, `Search`, `Session`, `Setup`, `Shortcuts`, `SitePermissions`, `Storage`, `Sync`, `Windows`), each applying itself to the read model; `CoreChange.swift` collects what a batch announces |
| `ReadModel/` | The observed models: workspace, Space, sidebar, archive, history, window state, favicon assets, observed list and set |
| `Seeds/` | Typed seeds of session records for tests, previews and first install; `Fixtures/` holds `#if DEBUG` readers and seeds |
| `CrestCore.swift`, `CrestCore+<Area>.swift` | The connection: intents, queries, wake handling; engines, shortcuts, storage, windows |
| `CoreState.swift`, `CoreState+<Area>.swift` | The read model root and its session, engine and storage views |
| `WireCoding.swift`, `CoreNamedValue.swift` | Reading the core's bytes and generated fixed sets that cross as names |
| `Rejection+LocalizedError.swift`, `Error+PersonFacingDescription.swift` | What a refused intent tells the person |
| `CloseRequest.swift`, `DataDeletionRequest.swift` | Requests the core prepares for closing and erasing profile data |
| `AppConfiguration+Device.swift`, `DevicePlatform+Current.swift`, `TabContent+Factories.swift`, `PagePresentation+Surface.swift`, `ImportSpaceNames+Resolving.swift` | Platform extensions on contract types |

## Depends on

`CrestCoreABI` (the C headers in `CrestContracts/include/`), the native core
library built from `CrestCore/`, Foundation, Observation and Synchronization.
Consumed by `Application/`, `Features/`, the other Infrastructure folders and
the platform trees.

## Rules

- Never hand-edit `Generated/`; change the C# contract and run `Scripts/control-plane/generate-contracts.sh` (`Documentation/Architecture/ControlPlane.md`, "The typed contract"; each generated file's "Do not edit" header).
- A new change applies itself in `Changes/<Area>/<Change>+CoreState.swift`; a case without its logic does not compile (`Documentation/Architecture/ControlPlane.md`, "The typed contract").
- Only the changes `CrestCore` receives update `CoreState`; every value is stored before it is announced (`Documentation/Architecture/ControlPlane.md`, "The read model").
- Views must not read a whole read-model list's `.values`; a generator check refuses it (`Documentation/Architecture/ControlPlane.md`, "The read model").
- Tests and previews build sessions as typed seeds (`SessionState.Seed`) (`Documentation/Architecture/ControlPlane.md`, "The read model" and "Resolved values and seeds").
- The core refuses a schema fingerprint other than its own, so Swift and the core ship from the same contracts (`Documentation/Architecture/ControlPlane.md`, "The C ABI").
- An engine contract change regenerates `crest_engine_contract.h`, an input of the Chromium engine key, so it needs a newly published engine (`Scripts/control-plane/chromium_engine.py`; `AGENTS.md`, "Published Chromium engine").

## Read next

`Documentation/Architecture/ControlPlane.md` ("The typed contract", "The read
model"), then `CrestCore/CONTEXT.md` for the C# side of the contract.
