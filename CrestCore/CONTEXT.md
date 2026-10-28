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
| `src/CrestCore/Contracts/` | Typed contract records: intents, changes, rejections, queries, engine commands and events, read models |
| `src/CrestCore/Domain/` | Tab and Space behavior, durable state, navigation, sync policy; no JSON or native dependencies |
| `src/CrestCore/Application/` | Session commands, the session file (SQLite), imports, sync transitions, one folder per browser area |
| `src/CrestCore.Native/` | C exports for native callers and the generated wire codec (`Generated/`) |
| `tools/CrestCore.Generator/` | Writes the C# codec, the Swift models and codec, the C header and the C++ engine codec from the contract records |
| `tests/CrestCore.Tests/` | Behavioral contracts for the source areas |

The layout and namespace rules in full: [`README.md`](README.md).

## Depends on

The .NET SDK in `global.json`. Consumers: `CrestShared/Infrastructure/Core/`
(Swift), `CrestContracts/` (C ABI), the Chromium host (C++ engine codec).

## Rules

- Contracts use neither Domain nor Application; Domain uses only Contracts (`README.md`).
- Decode JSON at an input boundary, apply typed domain objects, encode at the output (`README.md`).
- Messages carry their own behavior; no type switches or operation strings (skill, "Code style").
- After changing a contract, run `Scripts/control-plane/generate-contracts.sh`; the lint and the Apple core build fail while generated files are stale (`Documentation/Architecture/ControlPlane.md`).
- An engine command or event change regenerates `CrestContracts/include/crest_engine_contract.h`, which is in the Chromium engine key: it needs a published engine (`../CrestEngines/Chromium/CONTEXT.md`).
- Preserve the protocol and C ABI when moving files; namespaces stay stable (`README.md`).
- Before committing: `Scripts/control-plane/lint-dotnet.sh` and the .NET tests.

## Read next

`Documentation/Architecture/CoreArchitecture.md` and `ControlPlane.md`, then
the `Application/` or `Domain/` folder for the area being changed.
