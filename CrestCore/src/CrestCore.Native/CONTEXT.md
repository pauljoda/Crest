# CrestCore.Native

The shared library native callers load: C exports that adapt the hand-written
C ABI to `CrestApp`, and the generated wire codec. It is published with
NativeAOT, so no managed runtime ships with the app, and links the system
SQLite the session file uses.

## Goal

A thin, synchronous, handle-based boundary: bytes in the generated wire
format cross it, typed messages come out, and nothing crosses as JSON.

## Contents

| Path | What it is |
| --- | --- |
| `Exports/Exports.cs` | The handle sequence and `crest_core_abi_version` |
| `Exports/AppExports.cs` | `crest_app_*` (create, restore, destroy, set wake, end turn, settle sync, drain, dispatch, query), `crest_core_answer`, `crest_buffer_free` |
| `Exports/EngineExports.cs` | `crest_engine_register`, `report`, `ask`, `unregister`: an engine binding's function table and its reports |
| `Wire/` | `WireReader` and `WireWriter` for the positional wire format; `WireFormatException` for malformed bytes |
| `Generated/` | `ContractCodec.g.cs`, written by the contract generator |
| `CrestCore.Native.csproj` | NativeAOT shared library settings and the system SQLite link |

## Depends on

`CrestCore/src/CrestCore` (`Application/`, `Contracts/`). Its entry points
are declared in `CrestContracts/include/crest_core.h`, `crest_app.h` and
`crest_engine.h`. Built by `Scripts/control-plane/build-apple-core.py` and
`package-apple-core.py`, linked by `project.yml`; uses the system SQLite
(`libsqlite3`, `CrestCore.Native.csproj`); checked by `CrestContracts/tests/native_abi.c` and
`engine_abi.cc`.

## Rules

- Never hand-edit `Generated/`; change the contract and run `Scripts/control-plane/generate-contracts.sh` (`Documentation/Architecture/ControlPlane.md`, "The typed contract").
- Exports only adapt native callers to the application layer; browser rules stay in `Domain/` and `Application/` (`CrestCore/README.md`).
- Preserve the C ABI when moving or renaming code; native callers keep their type names (`CrestCore/README.md`).
- `crest_app_create` refuses any schema fingerprint but its own, so a stale core fails at launch (`Documentation/Architecture/ControlPlane.md`, "The C ABI").
- Status codes stay identical to the `CREST_*` macros in `crest_core.h` (`CrestCore/src/CrestCore/Application/Status/CoreStatus.cs`, its doc comment).
- The hand-written headers are Chromium engine inputs: changing them needs a published engine (`Scripts/control-plane/chromium_engine.py`, its input list; `AGENTS.md`, "Published Chromium engine").
- Apple silicon only: keep builds arm64 (`CONTRIBUTING.md`, "Validation").

## Read next

`CrestContracts/README.md`, `Documentation/Architecture/ControlPlane.md`
("The C ABI", "Build workflow").
