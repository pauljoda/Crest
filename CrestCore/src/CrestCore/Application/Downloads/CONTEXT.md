# Downloads

The downloads area: this run's download ledger and the changes each download
intent or engine report publishes. Both engines run downloads as their own
and report them; the core keeps phases, order, progress and ETA, risk, where
each file goes, approval and retention. The binding keeps the file handling.
Nothing here is persisted or synced.

## Goal

One set of download and risk decisions for both engines, with dangerous files
asked about before they have a place.

## Contents

| Path | What it is |
| --- | --- |
| `Downloads.cs` | The area: the ledger and the changes each intent publishes |
| `EngineDownloads.cs` | What one engine download report needs: its feed and the commands it causes |
| `EngineDownloadStage.cs`, `EngineDownloadStop.cs` | What each reported state and interruption means for a record |
| `EngineDownloadQuestion.cs` | What a download prompt asks: destination, keeping a warned file, continuing a dangerous one |
| `Intents/` | `DownloadIntent` and its cases: begin, assess risk, await and answer approval, destination, transfer, pause, resume, restart, cancel, fail, finish, remove, expire, acknowledge, block automatic downloads |
| `Events/` | `EngineDownloadEvent` and its cases: a download changed, a destination requested |
| `Queries/` | `DownloadProgress` (progress and ETA from engine samples) and `DownloadRisk` |

## Depends on

`Domain/Downloads/` (`DownloadLedger`, `DownloadFilename`),
`Contracts/Downloads/`, and `CrestApp` for the pages, device and prompts a
report touches. `Application/Closing/` asks before quitting with downloads in
progress. Swift's side is `CrestShared/Infrastructure/Downloads/`.

## Rules

- Each case overrides its family's `Apply` in its own file; an event that does not apply to a record's phase publishes nothing (`CrestCore/src/CrestCore/Application/Downloads/Downloads.cs`, its doc comment; `Documentation/Architecture/ControlPlane.md`, "The typed contract").
- A dangerous file is asked about before it has a place; a download without the person's gesture passes the site's automatic-download choice (`Documentation/Architecture/ControlPlane.md`, "Page lifecycle", Downloads).
- `PauseDownload` and `ResumeDownload` validate the record and Space access before commanding the owning engine; resuming never approves a risk warning (`Documentation/Architecture/ControlPlane.md`, "Page lifecycle", Downloads).
- The engine contract fixes the spelling of download states and interruptions; their meaning is declared here, not in the binding (`CrestCore/src/CrestCore/Application/Downloads/EngineDownloadStage.cs` and `EngineDownloadStop.cs`, their doc comments).
- Download risk decisions are a security contract worth a permanent test (`.agents/skills/crest-contribution/SKILL.md`, "Tests").

## Read next

`Documentation/Architecture/ControlPlane.md` ("Page lifecycle", Downloads),
then `CrestCore/tests/CrestCore.Tests/Downloads/`.
