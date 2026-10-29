# CrestCore.Generator

The contract generator. It loads every type the core exports in the
`CrestCore.Contracts` namespace, wherever its file sits, builds one schema
with a fingerprint, and writes the C# codec, the Swift models and codec, the C
tag header and the C++ engine codec. It reads each record's data and ignores
its methods. Run it through `Scripts/control-plane/generate-contracts.sh`.

## Goal

One schema: no wire tag spelled in source and no model written twice by hand,
with stale output caught before it builds.

## Contents

| File | What it is |
| --- | --- |
| `Program.cs` | Entry point: writes the outputs, or with `--check` fails when any is stale; refuses Swift sources that call a wire initializer or read a read-model object's whole record |
| `ContractSchema.cs` | The contract closure from the roots, wire tags by ordinal name order, fixed sets, byte limits, the schema and engine fingerprints |
| `CSharpCodecEmitter.cs` | `CrestCore/src/CrestCore.Native/Generated/ContractCodec.g.cs` |
| `SwiftEmitter.cs` | `CrestShared/Infrastructure/Core/Generated/CoreContracts.generated.swift` and `CoreCodec.generated.swift` |
| `CHeaderEmitter.cs` | `CrestContracts/include/crest_contracts.h`: tags and fingerprints |
| `CppCodecEmitter.cs` | `CrestContracts/include/crest_engine_contract.h`: the engine contract in portable C++20 without exceptions |
| `Naming.cs` | Spellings the outputs derive from C# names |
| `CrestCore.Generator.csproj` | Console project over `CrestCore` |

## Depends on

`CrestCore/src/CrestCore` (the contract records and their attributes in
`Contracts/Core/`). Run by `Scripts/control-plane/generate-contracts.sh`, and
with `--check` by `Scripts/control-plane/lint-dotnet.sh`; covered by
`CrestCore/tests/CrestCore.Tests/Interop/ContractCodecTests.cs`.

## Rules

- Outputs are never edited by hand; change the contract or the emitter and regenerate (`Documentation/Architecture/ControlPlane.md`, "The typed contract").
- The lint and the Apple core build fail while generated files are stale (`Documentation/Architecture/ControlPlane.md`, "The typed contract").
- A fixed set's tag is its index in `All`; an `[OpenSet]` never crosses by tag (`Documentation/Architecture/ControlPlane.md`, "The typed contract").
- The generator never defines a stored or synced key (`Documentation/Architecture/CoreArchitecture.md`, "Modeling rules").
- `crest_engine_contract.h` is a Chromium engine input, so an emitter change that alters it needs a published engine (`Scripts/control-plane/chromium_engine.py`, its input list; `AGENTS.md`, "Published Chromium engine").
- Attributes such as `[NormalizedOnConstruction]` and `[Observed]` change no wire bytes and stay out of the fingerprint (`CrestCore/src/CrestCore/Contracts/Core/ContractAttributes.cs`, their doc comments).

## Read next

`Documentation/Architecture/ControlPlane.md` ("The typed contract", "The read
model"), then the emitter for the output being changed.
