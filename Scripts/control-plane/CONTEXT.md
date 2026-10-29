# Scripts/control-plane

Tooling for the portable core and the Chromium engine: installing the .NET
SDK, building and packaging the native core for Apple targets, regenerating
the contract codecs, and preparing, building, keying and publishing the
maintained Chromium fork.

## Goal

Build the core and the engine reproducibly, and name each prebuilt engine by
a key over exactly the inputs that change it.

## Contents

| File | What it is |
| --- | --- |
| `generate-contracts.sh` | Regenerates the core codec, the Swift models under `CrestShared/Infrastructure/Core/Generated/`, `CrestContracts/include/crest_contracts.h` and `crest_engine_contract.h` |
| `install-dotnet.sh`, `lint-dotnet.sh` | The pinned .NET SDK for CI; core analyzer, style and whitespace checks plus `generate-contracts.sh --check` |
| `build-apple-core.py`, `package-apple-core.py` | The NativeAOT core for an Xcode target; the iOS library packaged as a framework |
| `build-experiment.sh`, `build-ios-experiment.sh` | Managed and native ABI checks, then an isolated `CrestNativeCore` app for macOS or Simulator |
| `prepare-chromium.py`, `apply-chromium-host.py`, `configure-chromium.py`, `build-chromium-baseline.py` | Prepare the pinned upstream tree, install the host overlay, configure and build: engine inputs |
| `chromium_engine.py` | The engine key: `INPUTS` lists every file it hashes |
| `chromium_artifact.py` | Requires a complete published engine matching the key |
| `chromium-fork.py`, `chromium_fork.py` | The fork CLI and its module: patch fork and persistent build workspace |
| `package-chromium-host.py` | Assembles and signs the Chromium host, as an isolated experiment or the product identity |
| `publish-chromium-engine.py`, `publish-chromium-update.py` | Publish a built engine under its key; commit, publish and open the review for an upstream update |
| `install-chromium-runner.py` | Installs the dedicated GitHub Actions runner in the build workspace |

## Depends on

`CrestCore/` (the generator in `CrestCore/tools/CrestCore.Generator/` and
`CrestCore/src/CrestCore.Native/`), `CrestContracts/`, `CrestEngines/Chromium/`.
Called by `project.yml` build phases (`build-apple-core.py`),
`.github/workflows/` and `ci_scripts/ci_post_clone.sh` (`install-dotnet.sh`).

## Rules

- Changing `prepare-chromium.py`, `apply-chromium-host.py`, `configure-chromium.py` or `build-chromium-baseline.py` needs a maintainer-published engine; say so in the pull request (`AGENTS.md`, "Published Chromium engine").
- Only maintainers publish engines (skill, "Pull request"; `AGENTS.md`, "Published Chromium engine").
- After changing a contract record, run `generate-contracts.sh`; never hand-edit its outputs (`CrestContracts/README.md`).
- A core library passed through `CREST_CORE_LIBRARY_DIR` or `CREST_CORE_FRAMEWORK_DIR` must match the checked-out contracts (`Documentation/Architecture/ControlPlane.md`, "Build workflow").
- Experiment builds launch with an isolated session (`Documentation/RepositoryGuardrails.md`, "Isolated validation sessions").

## Read next

`Documentation/Architecture/ControlPlane.md` ("Build workflow"),
`CrestEngines/Chromium/README.md` ("Releasing") and
`CrestEngines/Chromium/ForkMaintenance.md`.
