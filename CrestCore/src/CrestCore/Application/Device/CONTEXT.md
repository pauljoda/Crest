# Device

`Device`: what belongs to this device rather than to a session. Its windows
and what each shows, per-site engine choices, site permissions, shortcuts,
link preferences and routes, the search catalog, palette memory, setup and
import, and connected agents. It keeps them in the device store (`device_*`
tables beside the session), adopts what earlier releases kept once, and never
syncs any of it.

## Goal

Window and device rules decided by the core, so both platforms show, reopen
and route the same way.

## Contents

| Path | What it is |
| --- | --- |
| `Device.cs` and `Device.*.cs` | The device, split by purpose: agents, launch, links, palette, records, search catalog, setup draft and flow, shortcuts, site engines, site permissions, windows |
| `Window.cs`, `SavedWindow.cs`, `WindowFollowUp.cs` | A window and what it shows; the record a saved window keeps; what a session command chose for its window to show next |
| `DeviceRecords.cs`, `DeviceAdoption.cs` | Records the device store keeps; the once-only adoptions under their markers |
| `SiteEngineLedger.cs`, `AgentSessions.cs`, `KeptSetupDraft.cs` | Per-site engine choices; connected agents (memory only); an unfinished setup kept for the next launch |
| `SearchCatalogDocument.cs`, `PaletteMemoryDocument.cs` | JSON documents the device store keeps |
| `Legacy*.cs` | Formats earlier releases saved, adopted once: window records, link preferences, setup draft |
| `Intents/` | One subfolder per device family: `Windows/`, `SiteEngines/`, `SitePermissions/`, `Links/`, `Shortcuts/`, `Search/`, `Palette/`, `Setup/`, `Agents/` |
| `Queries/` | Device queries: launch windows and setup, link and external routing, site decisions, Dock menu, drop targets, recent tabs, swipe neighbours |
| `Questions/` | `LinkActivation`, what an engine asks when a person activates a link |

## Depends on

`Domain/` (shortcuts, site permissions, palette, search, spaces),
`Contracts/Windows/` and the device contracts, `Application/Storage/` for the
device store, `Application/Session/` for the workspaces its windows show.

## Rules

- Which Space and tab a window shows is device state, never session state; the device repairs every other window after a commit (`Documentation/Architecture/ControlPlane.md`, "Windows belong to the device" and "Sessions and commands").
- Device state is saved in the device store, memory-only Spaces' choices stay in memory, and none of it syncs (`Documentation/Architecture/ControlPlane.md`, "State the core keeps").
- The device store's tables are additive so older builds ignore them (`Documentation/Architecture/ControlPlane.md`, "Storage").
- What an older release kept is adopted once under an append-only marker, and the old values stay readable (`Documentation/Architecture/ControlPlane.md`, "Upgrading an installed session").
- Each device family's case overrides its `Apply` in its own file under `Intents/` (`Documentation/Architecture/ControlPlane.md`, "The typed contract").
- Crest never opens a window the person did not ask for (`.agents/skills/crest-contribution/SKILL.md`, "Windows and UI").

## Read next

`Documentation/Architecture/ControlPlane.md` ("Windows belong to the
device"), `Documentation/LinkOpeningPolicy.md` for links, then
`CrestCore/tests/CrestCore.Tests/Windows/`.
