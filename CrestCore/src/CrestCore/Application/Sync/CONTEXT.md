# Sync

The core's side of iCloud sync. `NativeSyncAuthority` is attached to the
persistent workspace and owns the accepted sync journal: it stages every
accepted session revision, merges incoming records, and answers what to
upload. `CloudSyncControl` decides what the sync controller does next; the
platform's CloudKit transport only takes the steps it is given.

## Goal

Deterministic merging and ordering owned by the core, with the platform
reduced to moving bytes to and from CloudKit.

## Contents

| Path | What it is |
| --- | --- |
| `NativeSyncAuthority.cs`, `NativeSyncTransaction.cs` | The sync component of the persistent session and its one-at-a-time journal transactions |
| `NativeSyncJournal.cs`, `SyncJournalRecord.cs`, `NativeSyncCheckpointCodec.cs` | Immutable journal snapshots (`Stage`, `Merge`, `Replace`, `Overwrite`, `Acknowledge`) and their stored form |
| `SyncStager.cs`, `SyncStaging.cs`, `SyncUrgency.cs`, `SyncRemovals.cs` | Staging accepted revisions on a worker: why removals are deleted and how soon a revision stages |
| `NativeSyncProjection.cs`, `NativeSyncMaterializer.cs`, `NativeSyncEvaluator.cs`, `NativeSyncSessionTransition.cs`, `NativeSyncCompatibility.cs` | Session to records and back, and the rules between them |
| `IncomingSyncRecords.cs`, `SyncSessionRecord.cs`, `SyncedText.cs`, `SyncJson.cs`, `SyncWireField.cs`, `SyncRecordsFlawedException.cs` | Incoming records, synced values and the JSON boundary |
| `CloudSyncControl.cs` | The sync controller's state machine |
| `CloudTransportStore.cs`, `CloudTransportRecord.cs`, `CloudFieldWrite.cs`, `LegacyCloudTransportDocument.cs` | The transport's cursor, per-record server fields and flags in the device store |
| `Payloads/` | `SyncRecordBody`, one payload type per record kind (`SyncPayloadType`), tombstones, times |
| `Changes/` | The session changes, each naming the sync records it removed |
| `Intents/` | `CloudSyncIntent`, `CloudSyncControlIntent`, `CloudTransportIntent`; `Session/` (merges, replacements), `Control/` (controller steps), `Transport/` |
| `Queries/` | Records to upload, pending uploads, cloud comparisons and status |

## Depends on

`Domain/Sync/`, `Contracts/Sync/`, `Application/Session/` (the revisions it
stages), `Application/Storage/` (journal and session saved in one
transaction). The Swift transport is `CrestShared/Infrastructure/Sync/`.

## Rules

- Sync stays Apple-only; CloudKit is an OS service and the core owns records, merging, ordering and scheduling (`Documentation/Architecture/ControlPlane.md`, "Sync").
- Private and temporary workspaces cannot attach sync (`Documentation/Architecture/ControlPlane.md`, "Sync").
- A merge computes outside the core's lock and takes it only to commit with a revision check; session and journal are written in one transaction (`Documentation/Architecture/ControlPlane.md`, "Sync").
- Rules that differ by record kind belong to that kind's `SyncPayloadType`; members this build does not know are kept (`Documentation/Architecture/ControlPlane.md`, "Sync").
- A record the core cannot read or whose schema is newer is skipped and counted; a snapshot with any skipped record is refused whole (`Documentation/Architecture/ControlPlane.md`, "Sync").
- Each session change names the records it removed (`Change.RemovedRecords`) (`Documentation/Architecture/ControlPlane.md`, "Sync").
- Sync codec changes are a contract worth a permanent test (`.agents/skills/crest-contribution/SKILL.md`, "Tests").

## Read next

`Documentation/Architecture/ControlPlane.md` ("Sync", "Cross-engine sync
contract", "Isolated CloudKit review"), `Documentation/ARCHITECTURE.md`
("Data and synchronization"), then `CrestCore/tests/CrestCore.Tests/Sync/`.
