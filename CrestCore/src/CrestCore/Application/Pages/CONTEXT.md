# Pages

`Pages`: every page this device hosts, the core's identity for it, its owner
(a tab, Quick Window, Peek or Settings), its window and engine, its history
across engines and its live state. Owners open, hand over and release pages
through page intents; engine bindings report what happened as page events.
The open pages are never saved or synced; a tab's archive keeps a page's history.

## Goal

The core owns page identity and decides what each navigation, offered popup,
crash or rehost does, so both engines behave the same way.

## Contents

| Path | What it is |
| --- | --- |
| `Pages.cs` | The open pages, restore states and the rules they share; hands each message to `Apply` with a `PageTurn` |
| `Page.cs` | One hosted page: owner, window, engine, where it stands there, live state |
| `PageHistory.cs`, `PageHistory.Archive.cs` | A page's back and forward history across every engine it moved through; the form a tab's archive keeps across a relaunch |
| `PageGroup.cs` | An engine tab group an extension made and the folder that shows it |
| `PageEdit.cs` | The icon an engine last reported for a page's document |
| `TransientPage.cs` | A Quick Window's or Peek's page as a session intent reads it |
| `Intents/` | `PageIntent` and its cases: `OpenPage`, `MovePage`, `ReleasePage`, `Navigate`, `LoadAddress`, `RehostPage`, history steps, staged links, memory pressure |
| `Events/` | `PageEvent` and its cases: navigation started, committed, finished, failed; created, offered, closed, crashed; state, icon, group and history reports |
| `Queries/` | Page history entries, archived page history, whether a tab can return to its saved address |

## Depends on

`Contracts/Pages/` and `Contracts/Engines/`, `Application/Engines/` (the
registered bindings), `Application/Session/` and `Application/Device/` (the
tabs and windows that own pages). Engine commands reach the bindings through
`CrestApp` once its lock is released.

## Rules

- Every case overrides `PageIntent.Apply` or `PageEvent.Apply` in its own file under `Intents/` or `Events/` (`Documentation/Architecture/ControlPlane.md`, "Page lifecycle").
- Typed addresses and every first load go through `Navigate`, resolved by the Space's address and search rules before `LoadPage` (`Documentation/Architecture/ControlPlane.md`, "Page lifecycle").
- A report about a page the core no longer hosts, or another engine hosts, changes nothing (`Documentation/Architecture/ControlPlane.md`, "Page lifecycle").
- A page opened by another page runs in the opener's engine; a popup window becomes a Quick Window page in the opener's Space (`.agents/skills/crest-contribution/SKILL.md`, "Architecture" and "Windows and UI"; `Documentation/LinkOpeningPolicy.md`).
- A page's engine page lives in its Space's profile, so it moves only between Spaces of that profile (`CrestCore/src/CrestCore/Application/Pages/Page.cs`, its doc comment).
- The core refuses a page in a locked Space or one being deleted (`Documentation/Architecture/ControlPlane.md`, "Page lifecycle").

## Read next

`Documentation/Architecture/ControlPlane.md` ("Page lifecycle"),
`Documentation/Architecture/CoreArchitecture.md` ("Engines"), then
`CrestCore/tests/CrestCore.Tests/Pages/`.
