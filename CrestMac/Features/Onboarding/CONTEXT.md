# Onboarding

The Mac setup window: welcome, importing from installed browsers or a Crest
archive, reviewing and customizing the Spaces an import makes, choosing a
look, manual setup and completion. It also holds the Mac readers that find
installed browsers and read their saved passwords.

## Goal

A person moves into Crest from another browser in one reviewed pass, with the
core holding the setup flow and committing the import.

## Contents

| Path | What it is |
| --- | --- |
| `BrowserOnboardingWindow.swift` | The setup window, and bringing the browser forward once setup finishes |
| `BrowserOnboardingWindow/` | `Components/` (the pages: welcome, import, look, make, review, manual setup, completion; import previews, import sidebar, Space customization, window configurator), `Models/` (`BrowserOnboardingFlow`, the Mac side of the core's setup flow), `Services/` (discovery, data access, import commit, extension install), `Support/` (preview services and fixture, summary, window activation) |
| `Models/` | Import read coordination, Space review, `BrowserInstalledImportSource/` and `BrowserPasswordImport/` models |
| `Services/` | `LiveBrowserOnboardingImportReader` and `BrowserPasswordImport/` (reader, committer, safe storage secret) |
| `Support/` | `BrowserInstalledImportSource/` (detection, data folder access, file picker, access store) and `BrowserPasswordImport/` (SQLite reader, Chromium password crypto, Safe Storage access) |

## Depends on

`CrestShared/Features/Onboarding/` and `CrestShared/Features/DataPortability/`
for shared pages and previews, and `BrowserStore` for the core's setup and
import intents and queries and each Space's Keychain credential inventory;
Security, SQLite and CommonCrypto to read other browsers' saved passwords.
Opened by `CrestMac/App/Shell/BrowserMacWindows.swift`.

## Rules

- The core holds setup (step, queue, review, finishing) and reads other browsers' bookmarks and sessions; an import is one core intent (`Documentation/ARCHITECTURE.md`, "Data and synchronization"; `CrestMac/Features/Onboarding/BrowserOnboardingWindow/Models/BrowserOnboardingFlow.swift`).
- Imported passwords go to each Space's Keychain inventory, routed by the core's `ImportPasswordDestinations` query (`CrestMac/Features/Onboarding/Services/BrowserPasswordImport/BrowserPasswordImportCommitter.swift`).
- Import persistence and Keychain access are contracts worth a test; page layout and copy are not (skill, "Tests").
- Forced-onboarding launches use `CREST_ISOLATED_SESSION=1` so setup never touches real data (`Documentation/RepositoryGuardrails.md`, "Isolated validation sessions").
- Previews reuse the preview services and fixture in `CrestMac/Features/Onboarding/BrowserOnboardingWindow/Support/` and stay deterministic, never live discovery, Keychain or filesystem (`Documentation/RepositoryGuardrails.md`, "Feature organization").

## Read next

`Documentation/ARCHITECTURE.md` ("Data and synchronization"),
`CrestShared/Features/Onboarding/`, then
`CrestMac/Features/Onboarding/BrowserOnboardingWindow/Models/BrowserOnboardingFlow.swift`.
