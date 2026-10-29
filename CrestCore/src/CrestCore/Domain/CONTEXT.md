# Domain

The core's browser rules as typed objects: how a Space's tabs, folders and
splits change, who may see a Space, how addresses resolve and the palette
ranks, how search, shortcuts, site permissions and downloads decide, and how
sync orders records. No JSON and no native code: the application decodes at
its boundaries and hands these objects typed values.

## Goal

Each browser rule written once, on the object whose data it reads, so every
intent that needs it applies the same rule.

## Contents

| Folder | What it is |
| --- | --- |
| `Tabs/` | `BrowserTabCollection`, a Space's organization while one edit applies, split into partial files by purpose; `Batch/`, `Lifecycle/`, `Organization/` for selections, dismissal and recovery, folder trees and split members |
| `Spaces/` | `SpaceTemplate` (what a new Space starts as) and `SpaceAccessAuthority`, the process-local unlock grants |
| `Navigation/` | Typed addresses and the `AddressIndex` a Space's history keeps by address |
| `ExternalNavigation/` | `UrlScheme`: which schemes Crest keeps, refuses or hands to another app |
| `Palette/` | The command palette's query, ranking and memory; `Finders/` holds one finder per kind of result |
| `Search/` | Search templates, slots, locales and edits |
| `Shortcuts/` | Shortcut chords and the person's overrides |
| `SitePermissions/` | The per-Space site permission ledger and its records |
| `Downloads/` | `DownloadLedger`, this run's downloads, and download filenames |
| `Sync/` | Portable sync rules: order tokens, record stamps, synced addresses, sync preferences |
| `Translation/` | Automatic translation rules and language tags |
| `Identity/` | `IClock`, `IIdSource` and their system sources, edit timestamps, the runtime identity registry |
| `Errors/` | `BrowserRule` and `BrowserRuleException`, for stored or synced data that breaks a rule |
| `Csv/` | RFC 4180 reading and writing, used by password files |

## Depends on

`Contracts/` only (same assembly). Used by `Application/` and by contract records
that carry behavior; tests reach it
through `CrestCore/tests/CrestCore.Tests/Domain/` and the area folders.

## Rules

- Domain uses only the contracts: no JSON, no native or storage dependency (`CrestCore/README.md`).
- Inside the core, methods take the objects, not their identifiers; identities are plain `Guid` properties, no one-field wrappers (`Documentation/Architecture/CoreArchitecture.md`, "Modeling rules").
- A type owns its data and every behavior that depends on it: no sibling `*Policy`, `*Rules` or `*Helper` types (`.agents/skills/crest-contribution/SKILL.md`, "Code style"; `Documentation/Architecture/CoreArchitecture.md`, "Modeling rules").
- Fixed sets carry their behavior on their instances; methods never switch on a member (`.agents/skills/crest-contribution/SKILL.md`, "Code style").
- Members follow the section layout with `#region`; a large purpose moves to `Type.Purpose.cs` (`.agents/skills/crest-contribution/SKILL.md`, "Code style").

## Read next

`Documentation/Architecture/CoreArchitecture.md` ("Modeling rules", "The
core's model"), then the `Application/` folder that calls the rule.
