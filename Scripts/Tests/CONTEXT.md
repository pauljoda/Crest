# Scripts/Tests

The retained Python suite for the repository scripts: the release, version,
release-note, public-source, contribution-check, Xcode Cloud and Chromium
fork contracts. Standard-library `unittest`, one module per contract.

## Goal

Keep the scripts that gate releases and pull requests honest, so a change to
a script fails here before it fails in a release.

## Contents

| File | What it is |
| --- | --- |
| `test_chromium_fork.py`, `test_chromium_profile_adoption.py` | Upstream selection, build ownership and publication gates; profile migration that resumes after an interrupted launch |
| `test_release_workflow.py`, `test_release_build_ordering.py`, `test_release_publication_recovery.py` | Release preflight, Sparkle feed ordering, interrupted GitHub Release recovery |
| `test_release_notes.py`, `test_release_note_catalog.py`, `test_release_note_publication.py` | The release-note catalog and its per-channel publication |
| `test_version_contract.py` | The semantic-version contract |
| `test_direct_distribution_contract.py`, `test_xcode_cloud_configuration.py`, `test_cloudkit_environment_configuration.py` | Direct macOS signing, the Xcode Cloud workflow, the CloudKit environment |
| `test_contribution_checks.py`, `test_public_source_contract.py`, `test_repository_guardrails.py` | The pull request checks, the public-source gate, the repository guardrails |

## Depends on

The scripts in `Scripts/` and `Scripts/control-plane/` that each module
imports. Run by `Scripts/validate.sh` and by the CI workflows in
`.github/workflows/`.

## Rules

- Run with `python3 -m unittest discover -s Scripts/Tests` (`Documentation/RepositoryGuardrails.md`, "Focused guard tests").
- Keep only durable contracts; remove temporary probes before handing off (`AGENTS.md`, "Test retention and cleanup").
- One focused behavioral test at the owning layer, no source-text assertions (skill, "Tests").

## Read next

`Documentation/RepositoryGuardrails.md` ("Focused guard tests"), then the
script the module covers.
