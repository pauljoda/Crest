# Contracts

Everything that crosses the core's boundary, as C# records and fixed sets in
the `CrestCore.Contracts` namespace: intents, queries, changes, rejections,
engine commands and events, and the read models they carry. The generator
reads these types to write every codec and the Swift models, so this folder is
the one schema.

## Goal

Name every message and every value the platforms and engines exchange with
the core once, typed, so no model is written twice by hand.

## Contents

| Folder | What it is |
| --- | --- |
| `Core/` | The message roots (`Change`, `Rejection`, `Configuration`, `AppConfiguration`), `Rejected`, and the attributes the generator reads (`[HoldsSecrets]`, `[Localized]`, `[NormalizedOnConstruction]`, `[Observed]`, `[MessageLimit]`) |
| `Session/` | The session's read model (`SessionState`, `SpaceState`, `TabState`, folders, splits, history, preferences) and its messages, one subfolder per session concern, such as `Tabs/`, `Spaces/`, `Changes/` and `Workspaces/` |
| `Windows/` | Window state, split column shares, Dock menu commands |
| `Pages/` | A page's phase, live state, security, snapshot and presentation |
| `Engines/` | Engine kinds, capabilities, roster and preferences, engine commands and events; `Presentations/`, `Requests/`, `SiteEngines/` |
| `Sync/` | Sync record kinds, versions, flaws and staging failures; `Control/` and `Transport/` for the cloud controller and transport |
| `Downloads/` | Download phases, failures, risk facts and assessment, telemetry |
| `Credentials/` | Credential records, capture and save plans, password recipes; `Files/` for password-file import and export |
| `Passkeys/` | Passkey access and authorization state |
| `Authentication/` | HTTP authentication challenges and how they are answered |
| `Prompts/` | Prompt messages and the credential an authentication prompt returns |
| `SitePermissions/` | Site origins, permissions and decisions, blocked popups, notification requests |
| `ContentBlocking/` | Content rule lists the engines compile |
| `DataDeletion/` | Browsing-data categories and ranges, website-data kinds, stored sites |
| `Links/` | Link behavior, routes and routing context, external link destinations, remembered sites |
| `Navigation/` | `WebAddress` and navigation queries |
| `Origins/` | Origin queries and local-document facts |
| `Search/` | Built-in and custom search providers, the search catalog and choices |
| `Palette/` | Command palette activation, scopes, sections, row kinds, queries |
| `Shortcuts/` | Shortcut commands, menus, sections and special keys |
| `Setup/` | The setup and import-review flow: draft, steps, phases, looks, import queue |
| `Portability/` | Import sources, export formats, portability queries and rejections |
| `Agents/` | Agent activity, preferences and session reach |
| `Closing/` | Close-preparation results |
| `Media/` | Page media-session reports |
| `Storage/` | What an installed release kept, as the host hands it to the core |
| `Devices/` | `DevicePlatform` and memory pressure levels |
| `Limits/` | `CapacityLimits`, the counts the core enforces |
| `GettingStarted/` | `PracticeTab`, the Getting Started practice tabs |

Message records that carry their own behavior keep this namespace but live
beside the area that receives them, under `Application/` (`CrestCore/README.md`).

## Depends on

Nothing outside the assembly; within it, some records reach `Domain/` or
`Application/` for the behavior they carry. Consumed by `Domain/`, `Application/`,
`CrestCore/src/CrestCore.Native` and `CrestCore/tools/CrestCore.Generator`, and through the generated
code by `CrestShared/Infrastructure/Core/Generated/` and `CrestContracts/include/`.

## Rules

- `CrestCore/README.md` keeps contracts free of Domain and Application except a message that carries its own behavior, but some state records already use both (for example `CrestCore/src/CrestCore/Contracts/Session/SpaceState.cs`); confirm with the maintainer before adding such a dependency.
- Every message is a named record; rule failures are rejection objects, never strings (`Documentation/Architecture/CoreArchitecture.md`, "Modeling rules").
- A fixed set is a sealed class with static instances; its wire tag is its index in `All`, so `All` only grows at the end (`Documentation/Architecture/ControlPlane.md`, "The typed contract").
- A record that holds a password is `[HoldsSecrets]`; `CrestCore/tests/CrestCore.Tests/Credentials/SecretContainmentTests.cs` checks nothing stored or synced reaches it (`Documentation/Architecture/ControlPlane.md`, "The typed contract").
- No source spells a wire tag; after changing an exported contract record, fixed set, enum it references or attribute the generator reads, wherever it is declared, run `Scripts/control-plane/generate-contracts.sh` (`Documentation/Architecture/ControlPlane.md`, "The typed contract").
- An engine command or event change regenerates `crest_engine_contract.h`, a Chromium engine input that needs a published engine (`Scripts/control-plane/chromium_engine.py`, its input list; `AGENTS.md`, "Published Chromium engine").
- Contract field names never define a stored or synced key (`Documentation/Architecture/CoreArchitecture.md`, "Modeling rules").

## Read next

`Documentation/Architecture/ControlPlane.md` ("The typed contract", "Resolved
values and seeds"), then `CrestCore/tools/CrestCore.Generator/` for how a type is emitted.
