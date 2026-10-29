# CrestCore.Tests

The core's permanent xUnit suite: behavioral contracts for each source area,
a folder per browser area. It references `CrestCore`, `CrestCore.Native` and
the generator, and sees the core's internals (`InternalsVisibleTo`), so tests
drive the real authorities and, in `Interop/`, the real C exports.

## Goal

Lock the contracts that break silently (persistence and migration, sync,
ownership, privacy and security decisions) at the layer that owns them.

## Contents

| Folder | What it is |
| --- | --- |
| `Session/` | Session authority, intents, change derivation, stored format, Space locks, borrowed and transient workspaces; `Fixtures/` holds saved-session JSON in the Swift encoder's shape; `RecordedIntents.cs` and `TestWorkspaces.cs` are shared helpers (test clock, identities, grants) |
| `Storage/` | The session file and adopting an installed release's session; `Fixtures/` holds an installed `session.sqlite` |
| `Sync/` | Journal staging, merge and materialization contracts, payload codec, conflicts, the cloud controller and transport |
| `Pages/` | Page lifecycle: navigation recording, rehosting, offered pages, crashes, groups, cross-engine history, prompts, close preparation |
| `Downloads/` | The download ledger, download risk policy and engine download reports |
| `Credentials/` | Credential policy, password import and export, and `SecretContainmentTests` |
| `Portability/` | Browser imports and Crest's browser-data file; `Fixtures/` holds one folder per browser profile, session or archive case |
| `Interop/` | The C exports driven through bytes (`AppClient`), the generated codec, app-level credential and search calls; `SetFixtures/` holds fixed sets the codec tests use and never send |
| `Domain/` | Domain rules: browsing policy, link decisions, organization, splits, Space access |
| `Windows/` | The device store and the Dock menu |
| `Setup/` | The setup flow and imported-password routing |
| `Launch/` | The launch plan |
| `Links/` | Link preferences |
| `Palette/` | Palette ranking, provider triggers and the address index |
| `Search/` | Search policy |
| `Shortcuts/` | The shortcut catalog and store |
| `SitePermissions/` | Origin policy and the site permission ledger and store |
| `DataDeletion/` | Website and browsing data deletion |
| `Agents/` | Agent sessions and reach |

## Depends on

`CrestCore/src/CrestCore`, `CrestCore/src/CrestCore.Native`,
`CrestCore/tools/CrestCore.Generator`; xUnit. Run with
`dotnet test tests/CrestCore.Tests` from `CrestCore/`
(`Documentation/Architecture/ControlPlane.md`, "Build workflow").

## Rules

- Default to no new test; add one only for a contract that breaks silently, and never test appearance or copy (`.agents/skills/crest-contribution/SKILL.md`, "Tests").
- One focused test at the owning layer; do not duplicate a shared contract across platform targets (`.agents/skills/crest-contribution/SKILL.md`, "Tests"; `AGENTS.md`, "Test retention and cleanup").
- Remove probes and temporary fixtures before handing off; never delete a failing test to go green (`.agents/skills/crest-contribution/SKILL.md`, "Tests"; `AGENTS.md`, "Test retention and cleanup").
- Run these tests and `Scripts/control-plane/lint-dotnet.sh` before committing a core change (`CrestCore/README.md`).
- No dated totals or investigation notes in the suite or its documents (`AGENTS.md`, "Test retention and cleanup").

## Read next

The skill's "Tests" section and `AGENTS.md` ("Test retention and cleanup"),
then the folder of the area being changed and its source `CONTEXT.md`.
