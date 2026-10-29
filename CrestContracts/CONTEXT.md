# CrestContracts

The C ABI of the portable core: the headers the Swift apps and the Chromium
binding compile against, and two native consumers that check the shared
library through them. `crest_core.h`, `crest_app.h` and `crest_engine.h` are
written by hand; the rest is generated from the core's contract records.

## Goal

One binary boundary between the .NET core and every native caller, whose wire
tags and fingerprints no source file spells by hand.

## Contents

| Path | What it is |
| --- | --- |
| `include/crest_core.h`, `crest_app.h`, `crest_engine.h` | The hand-written ABI: questions, the typed application API, the engine registration and report path |
| `include/crest_contracts.h` | Generated wire tags and the schema fingerprint |
| `include/crest_engine_contract.h` | Generated C++20 engine contract and codec, used by the Chromium binding |
| `include/module.modulemap` | Exposes the headers to Swift (`SWIFT_INCLUDE_PATHS` in `project.yml`) |
| `tests/` | `native_abi.c` and `engine_abi.cc`: C and C++ consumers of the real shared library |
| `README.md` | The contract in full: wire format, entry points, what each area owns |

## Depends on

The C# records in `CrestCore.Contracts`, through
`Scripts/control-plane/generate-contracts.sh` and
`CrestCore/tools/CrestCore.Generator`. Implemented by
`CrestCore/src/CrestCore.Native/`; imported as the `CrestCoreABI` module by
`CrestShared/Infrastructure/` (every app and test target's
`SWIFT_INCLUDE_PATHS` in `project.yml`); included by `CrestEngines/Chromium/`.

## Rules

- Never hand-edit `crest_contracts.h` or `crest_engine_contract.h`; change the contract record and run `Scripts/control-plane/generate-contracts.sh` (`CrestContracts/README.md`).
- Source never spells a wire tag; the generator owns them (skill, "Architecture"; `CrestContracts/README.md`).
- `crest_core.h`, `crest_app.h`, `crest_engine.h` and `crest_engine_contract.h` are Chromium engine inputs (`Scripts/control-plane/chromium_engine.py`, `INPUTS`); changing them needs a maintainer-published engine (`AGENTS.md`, "Published Chromium engine").
- The ABI is experimental; do not advertise external stability (`CrestContracts/README.md`).

## Read next

`README.md`, then `Documentation/Architecture/ControlPlane.md` ("The typed
contract", "The C ABI").
