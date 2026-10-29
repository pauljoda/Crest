# Portability

Reading other browsers' data (Arc, Chrome and other Chromium browsers,
Firefox, Zen, Safari) and Crest's own browser-data file, and writing exports.
Reading changes nothing and holds no lock, so the platform asks away from the
main thread; what it reads reaches a workspace only through `ImportSpaces`
and the other import intents, which check it again.

## Goal

Every import format read by the core with shared address and text
sanitation, so an import behaves the same on every platform.

## Contents

| Path | What it is |
| --- | --- |
| `Portability.cs`, `PortabilityModels.cs` | The area: reading, finding and exporting; plain data shared by readers |
| `InstalledBrowser.cs`, `InstalledBrowser.Search.cs` | Each browser Crest imports from: where it keeps bookmarks, sessions and passwords, and the readers for them |
| `ArcSidebar.cs`, `ZenSessions.cs`, `FirefoxSession.cs`, `SafariSession.cs`, `Chromium*.cs` | Session readers per browser; Chromium's SNSS session, pickles, extensions and profile order |
| `ChromeBookmarks.cs`, `SafariBookmarks.cs`, `BookmarkDraft.cs` | Bookmark readers and what they find |
| `SessionDraft.cs`, `SpaceSites.cs` | One window or Space a reader found; the sites a Space's saved passwords belong with |
| `Import*.cs` | Shared sanitation: addresses, text, dates, JSON values, files and folders an import reads |
| `PropertyList*.cs`, `MozillaLz4.cs` | Binary property lists (Safari) and Mozilla's compressed JSON (Firefox, Zen) |
| `BrowserData*.cs` | Crest's own browser-data file: Spaces, tabs, folders, splits, archive and history |
| `BookmarkFile.cs`, `ExportWriter.cs` | The Netscape bookmark export and the writer for each `ExportFormat` |
| `Queries/` | `FindChromiumBrowsers`, `FindImportData`, `ReadImport`, `ReadArchive` |

## Depends on

`Contracts/Portability/` and `Contracts/Setup/`, `Domain/Errors/`; held by
`CrestApp`, and `ExportWorkspace` writes through it; the
import intents in `Application/Session/Intents/Imports/` and the setup flow in
`Application/Device/Intents/Setup/` apply what it reads. Password files are
`Application/Credentials/`.

## Rules

- Import readers share URL and whitespace sanitation and keep their own title limits, fallbacks and errors; an import is one core intent saved with its sync journal (`Documentation/ARCHITECTURE.md`, "Data and synchronization").
- Archive readers validate identifiers and relationships before applying imported state (`Documentation/ARCHITECTURE.md`, "Data and synchronization").
- An export never carries passwords, cookies, website storage, permissions, downloads, favicons or extensions (`CrestCore/src/CrestCore/Application/App/Queries/ExportWorkspace.cs`, its doc comment).
- The browser-data file reads every schema version since the first (`CrestCore/src/CrestCore/Application/Portability/BrowserDataFile.cs`, its doc comment).
- Image bytes never reach the core; the platform matches imported tabs to their images (`CrestCore/src/CrestCore/Application/Session/NativeWorkspaceImport.cs`, its doc comment).
- Import fixtures live in `CrestCore/tests/CrestCore.Tests/Portability/Fixtures/`, copied by `CrestCore.Tests.csproj`; consolidate them and keep only those that protect a durable contract (`AGENTS.md`, "Test retention and cleanup").

## Read next

`Documentation/ARCHITECTURE.md` ("Data and synchronization"), then the reader
for the browser and `CrestCore/tests/CrestCore.Tests/Portability/`.
