# App

`CrestApp`, the core's typed application API, and the roots of the messages
it takes: `Intent`, `Query`, `EngineEvent` and `EngineQuestion`. One lock
serializes every call except the cloud transport's; changes the core starts
itself wait in a pending batch the host drains, and engine commands are
delivered once the lock is released.

## Goal

One entry point that hands each message to the area that owns it, publishes
the changes in order, and never lets an older change arrive after a newer one.

## Contents

| Path | What it is |
| --- | --- |
| `CrestApp.cs` | The API, its lock and its areas; partial files by purpose: `.Changes` (pending batch and wake), `.Engines` (bindings and command delivery), `.Storage` (the session file), `.Sync` (cloud transport intents), `.Workspaces` |
| `ChangeFeed.cs` | The changes one intent published, in order |
| `IQueryAnswers.cs`, `StandaloneAnswers.cs` | Who answers queries: an app answers all; `StandaloneAnswers` answers those that read no state, without an app |
| `Intents/` | `Intent` (each case routes itself with `Route`), `AdoptLegacySession`; `Workspaces/` for opening, borrowing and closing workspaces |
| `Queries/` | `Query<TAnswer>` and app-wide queries (`CanSend`, `PendingSave`, `ExportWorkspace`, `PaletteSuggestions`); `Standalone/` for `StandaloneQuery` cases such as `LaunchIsolation` and `NormalizeBranding` |
| `Events/` | `EngineEvent`, the root of every engine report, which routes itself |
| `Questions/` | `EngineQuestion`, what an engine asks while it waits; answered at once, changing nothing |

## Depends on

Every other `Application/` area, `Domain/` and `Contracts/`. Called by the C
exports in `CrestCore/src/CrestCore.Native/Exports/` and by the tests'
`CrestCore/tests/CrestCore.Tests/Interop/AppClient.cs`.

## Rules

- Each area handles its own messages: an intent routes itself to the area that owns its family, and each case's logic lives in its own file beside that area (`CrestCore/src/CrestCore/Application/App/CrestApp.cs`; `Documentation/Architecture/ControlPlane.md`, "The typed contract").
- An intent answers the pending changes first, then its own; self-started changes wait for the host's drain after its wake callback (`Documentation/Architecture/ControlPlane.md`, "The read model").
- A query answers itself under the app's lock unless it reads nothing the app holds (`AnsweredUnderLock`); a `StandaloneQuery` answers from the question alone (`Documentation/Architecture/ControlPlane.md`, "The typed contract").
- The cloud transport's intents compute on its thread and take the lock only to commit (`CrestCore/src/CrestCore/Application/App/CrestApp.cs`, its doc comment; `Documentation/Architecture/ControlPlane.md`, "Sync").
- A new area reached from here gets its own folder under `Application/` (`CrestCore/README.md`).

## Read next

`Documentation/Architecture/ControlPlane.md` ("The typed contract", "The read
model", "The C ABI"), then the area folder the message belongs to.
