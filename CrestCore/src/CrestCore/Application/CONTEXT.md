# Application

The core's running state and the handlers for every message: `CrestApp` and
its areas, each a folder that keeps its own state and the intents, queries
and events that act on it. It owns the stored and synced formats (JSON where
they require it) and `session.sqlite`, and calls the domain's typed rules.

## Goal

Each browser area receives its own messages and keeps its own state, so a new
message is one file beside the area it changes.

## Contents

| Folder | What it is |
| --- | --- |
| `App/` | `CrestApp`, the typed application API, its lock and change feed; the intent, query, engine event and engine question roots; standalone answers ([CONTEXT](App/CONTEXT.md)) |
| `Session/` | `NativeSessionAuthority`: each workspace's durable session, its intents, change derivation and the stored session codec ([CONTEXT](Session/CONTEXT.md)) |
| `Device/` | `Device`: windows and what each shows, per-site engines, site permissions, shortcuts, links, palette memory, setup, agents, the device store ([CONTEXT](Device/CONTEXT.md)) |
| `Pages/` | `Pages`: every open page, its engine, history and live state; page intents and engine page events ([CONTEXT](Pages/CONTEXT.md)) |
| `Sync/` | `NativeSyncAuthority`, the sync journal, payload codec, staging and the cloud sync controller ([CONTEXT](Sync/CONTEXT.md)) |
| `Portability/` | Reading other browsers' bookmarks, sessions and passwords; Crest's browser-data file; export writers ([CONTEXT](Portability/CONTEXT.md)) |
| `Downloads/` | This run's download ledger, download intents and engine download reports ([CONTEXT](Downloads/CONTEXT.md)) |
| `Credentials/` | Password-file reading and the stateless credential and passkey queries ([CONTEXT](Credentials/CONTEXT.md)) |
| `Storage/` | `SessionStorage`: `session.sqlite`, its parts, durability and the system SQLite binding |
| `Engines/` | `Engines`: the registered engine bindings and the default engine |
| `Access/` | `SpaceAccess`: locking and unlocking Spaces |
| `Prompts/` | `Prompts`: permission, authentication, script-dialog and extension-install questions waiting on the person |
| `Closing/` | `ClosePreparations`: asking pages whether they may close before a close or quit |
| `DataDeletion/` | Erasing and reading what the engines keep for a profile or site |
| `ContentBlocking/` | The balanced-protection rule query |
| `SitePermissions/` | The site-permission document earlier releases saved, adopted once |
| `Shortcuts/` | The shortcut document earlier releases saved, adopted once |
| `Status/` | `CoreStatus`, the status codes of the native entry points |

## Depends on

`Contracts/` and `Domain/`; the system SQLite through `LibraryImport`
(`Storage/Sqlite.cs`). Called by `CrestCore/src/CrestCore.Native`
(the C exports) and by `CrestCore/tests/CrestCore.Tests`.

## Rules

- Messages route and apply themselves: each case overrides its family's `Route`, `Apply`, `Edit` or `Answer` in its own file beside its area; no type switches (`Documentation/Architecture/ControlPlane.md`, "The typed contract").
- Message records here keep the `CrestCore.Contracts` namespace; area types use `CrestCore.Application` (`CrestCore/README.md`).
- Decode JSON at an input boundary, apply domain objects, encode at the output; JSON stays only in the native, persistence and sync formats this layer owns, such as the session, the device-store documents and sync (`CrestCore/README.md`).
- Stored and synced formats have hand-written codecs; the generator never defines a stored or synced key (`Documentation/Architecture/CoreArchitecture.md`, "Modeling rules").
- What each area keeps, saves and syncs is the table in `Documentation/Architecture/ControlPlane.md`, "State the core keeps".
- `CoreStatus` values stay identical to the `CREST_*` macros in `CrestContracts/include/crest_core.h` (`CrestCore/src/CrestCore/Application/Status/CoreStatus.cs`, its doc comment).
- Data-only records share their concept's file or a `Types` region; a type with behavior has its own file (`CrestCore/README.md`).

## Read next

`App/CONTEXT.md`, then the area's `CONTEXT.md`, then
`Documentation/Architecture/ControlPlane.md` for that area's section.
