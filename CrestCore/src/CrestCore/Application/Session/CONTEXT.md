# Session

`NativeSessionAuthority`: one workspace's durable browsing data (Spaces with
their profiles, tabs, folders, splits, history, archive, app preferences) as
immutable accepted states. Every edit is a `SessionIntent` that names its
window; the authority prepares it against the state it saw, commits it only if
that state is still current, and derives the changes it publishes.

## Goal

Every tab, folder, split, Space and history rule applied in one place, with
a stored format a rollback build still reads.

## Contents

| Path | What it is |
| --- | --- |
| `NativeSessionAuthority*.cs` | The authority, split by purpose: access, batches, borrowing, device, drops, history, lifecycle, moves, organization, pages, preferences, replacement, search, Spaces, sync, transient pages, workspace |
| `NativeSessionCheckpoint.cs`, `NativeSessionReplacement.cs`, `NativeSessionMaintenance.cs`, `SessionRepair.cs` | An encodable revision, a reserved state while it saves, checkpoint repair and retention |
| `SessionChanges.cs`, `SessionIdentities.cs` | The changes derived by comparing two accepted states; the identity checks each accepted state passes |
| `NativeWorkspaceImport.cs` | One import into a session and the identities it gives what it brings |
| `StoredSessionCodec*.cs` | The stored session format: every stored key and value spelling |
| `NativeEditTimestamp.cs` | Edit timestamps in the stored format |
| `Intents/` | `SessionIntent` and one file per case, by concern: `Tabs/`, `Lifecycle/`, `Batches/`, `Moves/`, `Drops/`, `Organization/`, `Spaces/`, `Preferences/`, `Records/`, `Search/`, `Transient/`, `Imports/`; `NavigateTab` |
| `Model/` | `SessionTabEvents`: which page image a tab adopts |
| `Queries/` | Session queries: `LaunchPlan`, `ImportPreview`, `ResolveAddress`, `SelectionPreview`, `SelectionSearch` |

## Depends on

`Domain/Tabs/`, `Domain/Spaces/`, `Domain/Navigation/`, `Contracts/Session/`;
`Application/Storage/` saves it, `Application/Sync/` stages its revisions,
`Application/Device/` owns the windows that show it.

## Rules

- Each case overrides `SessionIntent.Edit` in its own file under `Intents/`; the authority validates what comes back (`Documentation/Architecture/ControlPlane.md`, "Sessions and commands").
- The session holds browsing data only: what a window shows is device state, never stored here (`Documentation/Architecture/ControlPlane.md`, "Windows belong to the device").
- A locked Space refuses a prepared intent with `SpaceLocked` before it runs; deletion, raising protection and retention sweeps still apply (`Documentation/Architecture/ControlPlane.md`, "Locked Spaces").
- A borrowed workspace never edits its Space's settings (`BorrowedProfileRequiresOwner`) and is never saved or staged (`Documentation/Architecture/ControlPlane.md`, "Sessions and commands").
- Every stored key lives in `StoredSessionCodec`; contract field names never define one (`CrestCore/src/CrestCore/Application/Session/StoredSessionCodec.cs`, its doc comment; `Documentation/Architecture/CoreArchitecture.md`, "Modeling rules").
- Commits whose effects outside the core depend on the file save before they return (`Documentation/Architecture/ControlPlane.md`, "Storage").
- An intent that changes nothing publishes nothing (`CrestCore/src/CrestCore/Application/Session/Intents/SessionIntent.cs`, its doc comment).

## Read next

`Documentation/Architecture/ControlPlane.md` ("Sessions and commands",
"Storage", "Upgrading an installed session"), then the `Intents/` subfolder
for the change and `CrestCore/tests/CrestCore.Tests/Session/`.
