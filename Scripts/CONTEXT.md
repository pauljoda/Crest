# Scripts

Repository tooling: bootstrap, the checks the contribution workflow and CI
run, local validation, versioning and release-note tools, release
publication helpers, asset and catalog generators, and the control-plane
tooling for the core and the Chromium engine.

## Goal

Every check a pull request must pass can be run locally with the same script
CI runs.

## Contents

| Path | What it is |
| --- | --- |
| `bootstrap.sh` | First-run setup: generates the project, links the Claude Code skill, runs the version and identity checks |
| `check-architecture.py`, `check-swift-format.sh`, `check-public-source.py`, `check-contribution.py` | Layer and SwiftUI contracts, changed-file formatting, public-source contents, the pull request AI declaration and sign-offs |
| `set-version.sh`, `check-version.sh` | Patch and release-line bumps; the staged version and release-note check |
| `release_note_catalog.py`, `release_note_publication.py`, `generate-release-notes.py` | Validate `Documentation/ReleaseNotes.json`, advance per-channel cursors, render release copy |
| `validate.sh`, `validate-identity.sh`, `validate-cache-hygiene.sh` | Script tests plus macOS and iOS unit gates; required paths and identifiers; leftover build products |
| `audit-licenses.py`, `audit-periphery.sh` | License surface against `Config/ThirdPartyDependencies.json`; the optional dead-code evidence audit |
| `ci-changed-areas.py`, `next-release-build-number.py`, `resolve-published-release.py`, `reconcile-release-assets.py` | CI and release helpers called from `.github/workflows/` |
| `install-local-macos-release.sh` | Builds, signs and installs the dual-engine Mac app as the release workflow does |
| `render-roadmap.py` | Renders the managed section of `Documentation/ROADMAP.md` from GitHub issues |
| `generate-app-icon-palettes.py`, `pad-mac-app-icon.swift`, `generate-emoji-catalog.py`, `update-sf-symbol-catalog.py` | Asset and catalog generators |
| `control-plane/` | Core build and contract generation, Chromium fork preparation, build and publishing ([CONTEXT](control-plane/CONTEXT.md)) |
| `Tests/` | The retained Python suite for these scripts and the release contracts ([CONTEXT](Tests/CONTEXT.md)) |

## Depends on

zsh, Python 3, Git and ripgrep; Xcode, XcodeGen and the .NET SDK for the
build scripts (`CONTRIBUTING.md`, "Local setup"). Called by `.github/workflows/`
and `ci_scripts/` (`check-version.sh`).

## Rules

- Repository guard tooling stays compatible with the Python 3.9 bundled with Xcode (`Documentation/RepositoryGuardrails.md`, "Focused guard tests"); the Chromium and release tools need 3.11+ (`CONTRIBUTING.md`, "Local setup").
- No feature-specific source-topology tests; the repository-wide guards own dependency direction (`Documentation/RepositoryGuardrails.md`, "Focused guard tests").
- The formatter check only lints changed files; never run a repository-wide format (`Documentation/RepositoryGuardrails.md`, "Changed-file formatting").
- Periphery findings are evidence, never a reason to delete without proof (`Documentation/RepositoryGuardrails.md`, "Periphery evidence audit").
- Keep new scripts arm64-native (`CONTRIBUTING.md`, "Validation").
- A new `.agents/` or `.claude/` entry is rejected by `check-public-source.py` (`Documentation/RepositoryGuardrails.md`, "Focused guard tests").

## Read next

`Documentation/RepositoryGuardrails.md`, then `CONTRIBUTING.md` ("Validation").
