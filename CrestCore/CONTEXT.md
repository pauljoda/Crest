# CrestCore

The portable browser control plane, in C#. It owns Spaces, tabs, folders,
splits, windows, history, behavior preferences, page state and sync, and
decides navigation, download, content-blocking, permission and website-data
rules. Swift and the engines send it intents and events and apply the changes
it returns.

## Goal

Every browser rule lives here once, typed, so both platforms and both engines
behave the same way.

## Contents

| Path | What it is |
| --- | --- |
| `src/CrestCore/Contracts/` | Typed contract records: intents, changes, rejections, queries, engine commands and events, read models; the generator's one schema ([CONTEXT](src/CrestCore/Contracts/CONTEXT.md)) |
| `src/CrestCore/Domain/` | Tab, Space, navigation, palette, search, permission, download and sync-ordering rules as typed objects; no JSON or native dependencies ([CONTEXT](src/CrestCore/Domain/CONTEXT.md)) |
| `src/CrestCore/Application/` | `CrestApp` and one folder per browser area: session, device, pages, sync, storage (SQLite), portability, downloads, credentials ([CONTEXT](src/CrestCore/Application/CONTEXT.md)) |
| `src/CrestCore.Native/` | NativeAOT C exports (`crest_app_*`, `crest_engine_*`), the wire reader and writer, and the generated codec (`Generated/`) ([CONTEXT](src/CrestCore.Native/CONTEXT.md)) |
| `tools/CrestCore.Generator/` | Writes the C# codec, the Swift models and codec, the C tag header and the C++ engine codec; `--check` fails on stale output ([CONTEXT](tools/CrestCore.Generator/CONTEXT.md)) |
| `tests/CrestCore.Tests/` | The xUnit suite, one folder per area, with session, storage and portability fixtures ([CONTEXT](tests/CrestCore.Tests/CONTEXT.md)) |

The layout and namespace rules in full: [`README.md`](README.md).

## Depends on

The .NET SDK in `global.json`; the system SQLite (`libsqlite3`, linked by
`CrestCore.Native.csproj`). Consumers: `CrestShared/Infrastructure/Core/`
(Swift), `CrestContracts/` (C ABI), the Chromium host in `CrestEngines/Chromium/`
(C++ engine codec).

## Rules

- Domain uses only Contracts (`CrestCore/README.md`); the README's rule that contracts avoid Domain and Application has exceptions in the code (`src/CrestCore/Contracts/CONTEXT.md`).
- Decode JSON at an input boundary, apply typed domain objects, encode at the output (`CrestCore/README.md`).
- Messages carry their own behavior; no type switches or operation strings (`.agents/skills/crest-contribution/SKILL.md`, "Code style").
- After changing a contract, run `Scripts/control-plane/generate-contracts.sh`; the lint and the Apple core build fail while generated files are stale (`Documentation/Architecture/ControlPlane.md`).
- An engine command or event change regenerates `CrestContracts/include/crest_engine_contract.h`, which is in the Chromium engine key: it needs a published engine (`Scripts/control-plane/chromium_engine.py`, its input list; `AGENTS.md`, "Published Chromium engine").
- Preserve the protocol and C ABI when moving files; namespaces stay stable (`CrestCore/README.md`).
- Before committing: `Scripts/control-plane/lint-dotnet.sh` and the .NET tests (`CrestCore/README.md`).

## Read next

`Documentation/Architecture/CoreArchitecture.md` and `ControlPlane.md`, then
the `Application/` or `Domain/` folder for the area being changed.
