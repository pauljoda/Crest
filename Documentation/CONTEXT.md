# Documentation

Contributor references: architecture and ownership, browser behavior,
repository guardrails, distribution, the roadmap, the release-note catalog,
and the sources of bundled third-party marks. User help lives in
`HelpCenter/`. `README.md` is the index of what to read; this file only
routes to it.

## Goal

Describe lasting product behavior and contributor instructions, with each
rule written once.

## Contents

| Path | What it is |
| --- | --- |
| `README.md` | The index: where to start and which document covers what |
| `ARCHITECTURE.md` | Space isolation, data and sync, windows and scenes, credentials, the engine boundary, platform shape |
| `Architecture/` | Core architecture, the control plane, engine abstraction, content blocking, desktop Picture in Picture |
| `RepositoryGuardrails.md` | What the checks enforce: formatting, versions, release notes, architecture, feature organization, isolated sessions |
| `Distribution.md` | Release channels, signing, notarization, appcasts, release verification |
| `LinkOpeningPolicy.md`, `NativeTabs.md` | Where links and opened windows go; tabs with native content |
| `ReleaseNotes.json` | The release-note catalog, bundled into the apps and read by the release tools |
| `ROADMAP.md` | Public release outcomes; its managed section is rendered by `Scripts/render-roadmap.py` |
| `EngineLogos.md`, `GettingStartedLogos.md`, `SearchProviderLogos.md` | Sources of the third-party marks the app shows |

## Depends on

Nothing. Read by contributors and agents; `ReleaseNotes.json` is consumed by
`project.yml`, `Scripts/release_note_catalog.py` and the release workflows.

## Rules

- Only lasting behavior and instructions: no task reports, test totals, machine paths, screenshots or cleanup narratives (`AGENTS.md`, "Test retention and cleanup").
- Documentation is public: no private planning or machine-specific instructions (`CONTRIBUTING.md`, "Change discipline").
- Append release-note entries with a new kebab-case ID; never reuse, reorder or delete one (`AGENTS.md`, "Explicit release notes").
- `ROADMAP.md`'s marked section is generated from GitHub issues with `Scripts/render-roadmap.py --write`, which keeps the platform notes (`CONTRIBUTING.md`, "Community and planning").
- A new third-party asset passes `Scripts/audit-licenses.py` (`CONTRIBUTING.md`, "Validation").

## Read next

`README.md`, then the document the `ROUTING.md` row names.
