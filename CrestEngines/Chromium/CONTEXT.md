# CrestEngines/Chromium

Crest's maintained Chromium fork and its Swift adapter. The upstream recipe,
patches, overlay and C ABI headers form one versioned engine definition; the
expanded source and builds live outside the checkout. The release workflow
cannot build Chromium: it downloads a prebuilt engine named by a key over its
inputs.

## Goal

Ship Chromium as the default Mac engine behind the same adapter boundary as
WebKit, with every engine change reviewed beside its Swift caller.

## Contents

| Path | What it is |
| --- | --- |
| `fork.json`, `source.lock.json`, `host-inputs.json` | The upstream repository and channel, the pinned recipe, the host patch's inputs and outputs |
| `Patches/` | Crest's patches over upstream (`native-host.patch` selects the Crest window) |
| `Overlay/` | The BrowserWindow and engine implementation added to the source tree |
| `Apple/` | The Swift adapter: `ChromiumEngine`, `ChromiumPageAdapter`, runtime, extensions, presentations; `CrestChromiumHost.h` |
| `Composition/` | How the Mac app composes the engine |
| `ThirdParty/` | Provenance and retained licenses for adapted code |
| `README.md`, `ForkMaintenance.md` | The engine definition and releasing; workspace commands, CI, upstream updates |

## Depends on

`CrestContracts/include` (C ABI), the core's generated engine codec,
`Scripts/control-plane/` (prepare, apply, configure, build, publish).

## Rules

- The engine key (`Scripts/control-plane/chromium_engine.py`, `INPUTS`) covers `source.lock.json`, `host-inputs.json`, `Patches/`, `Overlay/`, `Apple/CrestChromiumHost.h`, four `CrestContracts/include` headers and four control-plane scripts. Changing any of them needs a maintainer-published engine; say so in the pull request (`AGENTS.md`).
- `crest_engine_contract.h` is generated from the core's engine contracts, so an engine command or event change is an engine-input change too.
- Swift adapter files other than `CrestChromiumHost.h` reuse the published engine.
- A new upstream release must apply every hunk without fuzz; milestones need `--allow-major` and review (`README.md`, "Maintained fork").
- Extensions run only in Chromium; a page opened by another page stays in the opener's engine (`Documentation/ARCHITECTURE.md`).

## Read next

`README.md` ("Releasing"), `ForkMaintenance.md`, and
`Documentation/Architecture/EngineAbstractionCompletion.md`.
