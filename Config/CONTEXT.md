# Config

Repository-wide configuration read by the build, the checks and the release
workflows: the public version, the architecture exception register, the
third-party dependency register, the Developer ID export options and the
debugger settings every app scheme sources.

## Goal

Keep each machine-read setting in one file that its owning script or
workflow validates.

## Contents

| File | What it is |
| --- | --- |
| `Version.xcconfig` | `MARKETING_VERSION`, the only source of Crest's public version |
| `ArchitectureGuardrails.json` | Exact, reasoned exemptions read by `Scripts/check-architecture.py` |
| `ThirdPartyDependencies.json` | Runtime dependencies and bundled data with their licenses and notices, read by `Scripts/audit-licenses.py` |
| `DeveloperIDExportOptions.plist` | Developer ID export for release packages (`.github/workflows/release.yml`, `Scripts/install-local-macos-release.sh`) |
| `Crest.lldbinit` | Debugger settings so the core runtime's signals never stop the app (schemes in `project.yml`) |

## Depends on

Nothing. Read by `project.yml`, `Scripts/`, `ci_scripts/` and
`.github/workflows/`.

## Rules

- Change the version only with `Scripts/set-version.sh`, stage it with the change, and pass `Scripts/check-version.sh --fix-commit`; never change `CURRENT_PROJECT_VERSION` (`AGENTS.md`, "Versioning completed work").
- A release-line change is an explicit maintainer decision (`CONTRIBUTING.md`, "AI-assisted contributions").
- An architecture exemption is exact, carries a reason, and is not precedent (`Documentation/RepositoryGuardrails.md`, "Architecture and Xcode 27 compatibility").
- A new runtime dependency needs a redistributable license, a preserved notice and a passing `Scripts/audit-licenses.py` (`CONTRIBUTING.md`, "Validation").

## Read next

`Documentation/RepositoryGuardrails.md` ("Fix commit versions",
"Architecture and Xcode 27 compatibility") and `Documentation/Distribution.md`.
