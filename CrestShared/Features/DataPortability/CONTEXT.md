# CrestShared/Features/DataPortability

The Import & Export section of Settings. The core reads other browsers' data
and Crest browser-data files and writes each export; this folder presents
the file panels, holds access to a picked file while the core reads it, and
reports progress and results.

## Goal

Move a person's browsing data in and out of Crest with the core doing every
read and write.

## Contents

| Path | What it is |
| --- | --- |
| `Components/BrowserDataPortabilitySection/` | The section, its model and operation status, export controls, document presenter, progress, footnotes and the macOS import requirement |
| `Models/` | `BrowserExportDocument`, the file an export saves |

## Depends on

`CrestCore/src/CrestCore/Application/Portability/` (import readers and the
export writer) through `BrowserStore`; `BrowserSpaceAccessController`.
Shown in `Settings/BrowserAdvancedSettingsPane/`.

## Rules

- An import is one core intent, saved with its sync journal before it returns (`Documentation/ARCHITECTURE.md`, "Data and synchronization").
- Archive readers validate identifiers and relationships before applying state (same).
- Import sanitation and limits live in the core's readers, never in Swift (same).
- Persistence and migration contracts are where tests belong, in the core (skill, "Tests").

## Read next

`Documentation/ARCHITECTURE.md` ("Data and synchronization"), then
`CrestCore/src/CrestCore/Application/Portability/`.
