# BrowserStore

`BrowserStore` is the per-window facade over the core. It reads what its
window shows from the core's read model (`core.state`) and sends the intents
that window's actions need: opening pages, organizing tabs and folders,
switching Spaces, history, credentials, launch. It holds no browser state of
its own; a `BrowserStoreFamily` groups the windows of one browsing mode.

## Goal

Every window action reaches the core as one typed intent, and every window
renders from the core's read model, so all windows agree before anything is
saved.

## Contents

| Path | What it is |
| --- | --- |
| `BrowserStore.swift` | The store: window identity, the shown Space and tab, its collaborators |
| `BrowserStore+<Purpose>.swift` | One file per purpose: `CoreCommands`, `Pages`, `Spaces`, `Folders`, `TabOrganization`, `CoreTabOrganization`, `TabBatch`, `TabLifecycle`, `DurableTabs`, `History`, `Credentials`, `AppPreferences`, `GettingStarted`, `Launch`, `Workspaces`, `ReadModel`, `Shown` |
| `BrowserPageDismissalAuthorizing.swift`, `BrowserTabCopying.swift`, `BrowserTabLinkProviding.swift` | Ports the window's page owner supplies: close confirmation, tab copies, tab addresses |
| `Family/` | `BrowserStoreFamily`: the windows of one browsing mode and their running Space deletions |
| `Fixtures/` | `#if DEBUG` hosting, seeding and snapshot helpers for tests and previews |
| `Models/` | Session revision, selection, multi-selection, tab batches, session projection and credential save plans |
| `Navigation/` | Next and Previous Space steps and swipe directions |
| `Protocols/` | `BrowserStoreInteractionObserving`: the weak observer for session reset and tab relocation |

## Depends on

`CrestCore` and `CoreState` (`Infrastructure/Core/`), `Domain/`, and the
Application stores it is composed with (link preferences, credential vault,
Space access). Consumed by every feature view and the platform shells.

## Rules

- Never change shared state from the store directly; add or use a core intent and apply the change it returns (skill, "Architecture").
- The store sends intents and answers what a window shows; it holds no browser state of its own (`Documentation/Architecture/ControlPlane.md`, "The read model").
- Make a core intent and a direct engine call visibly different at the call site (skill, "Architecture").
- Report session reset and tab relocation through the weak, domain-only observer; never construct or retain feature presentation (`Documentation/ARCHITECTURE.md`, "Platform shape").
- A large purpose moves to its own `BrowserStore+<Purpose>.swift` (skill, "Code style").
- Tests and previews build sessions as typed seeds (`SessionState.Seed`), not by editing the store (`Documentation/Architecture/ControlPlane.md`, "The read model").
- Imports follow the Application policy in `Scripts/check-architecture.py`.

## Read next

`Documentation/ARCHITECTURE.md` ("Windows on macOS"),
`Documentation/Architecture/ControlPlane.md` ("The read model", "Windows
belong to the device"), then the `BrowserStore+Purpose.swift` being changed.
