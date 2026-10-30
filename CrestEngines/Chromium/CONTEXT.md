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
| `Overlay/` | C++ and Objective-C++ added to the Chromium tree: the engine binding, the Crest `BrowserWindow`, user-data-directory adoption (see "Overlay" below) |
| `Apple/` | The Swift adapter: `ChromiumEngine`, `ChromiumPageAdapter`, runtime, extensions, presentations; `CrestChromiumHost.h` ([CONTEXT](Apple/CONTEXT.md)) |
| `Composition/` | The `Crest-Native-Host` resource marker bundled with the Chromium UI product |
| `ThirdParty/` | Provenance and retained licenses for adapted code |
| `README.md`, `ForkMaintenance.md` | The engine definition and releasing; workspace commands, CI, upstream updates |

## Depends on

`CrestContracts/include` (the C ABI and the generated C++ engine codec
`crest_engine_contract.h`), `Scripts/control-plane/` (prepare, apply,
configure, build, publish; `chromium_engine.py` names the engine), and the
engine port in `CrestShared/Infrastructure/Engines/`. The `CrestChromiumUI`
and `CrestChromiumUIProduct` targets in `project.yml` compile `Apple/`.

## Rules

- The engine key (`Scripts/control-plane/chromium_engine.py`, `INPUTS`) covers `source.lock.json`, `host-inputs.json`, `Patches/`, `Overlay/`, `Apple/CrestChromiumHost.h`, four `CrestContracts/include` headers and four control-plane scripts. Changing any of them needs a maintainer-published engine; say so in the pull request (`AGENTS.md`, "Published Chromium engine").
- `crest_engine_contract.h` is generated from the core's C# contract records, so an engine command or event change is an engine-input change too (the header's own comment; `Scripts/control-plane/chromium_engine.py`, `INPUTS`).
- Swift adapter files other than `CrestChromiumHost.h` reuse the published engine (`AGENTS.md`, "Published Chromium engine").
- A new upstream release must apply every hunk without fuzz; milestones need `--allow-major` and review (`README.md`, "Maintained fork").
- Every file under `Patches/` and `Overlay/` is hashed into the engine key, Markdown included, so those folders hold engine sources only; their notes live in this file (`Scripts/control-plane/chromium_engine.py`, `engine_key`).
- Extensions run only in Chromium (`Documentation/ARCHITECTURE.md`, introduction); a page opened by another page stays on its opener's engine (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Ownership").

## Overlay

The C++ and Objective-C++ sources `Scripts/control-plane/apply-chromium-host.py`
copies into the Chromium tree, at the paths they take there, after
`Patches/native-host.patch` applies. They let Chrome's own `Browser`, tab model
and extension system drive Crest's UI and report to the core, behind the same
engine contract as WebKit.

| Path in `Overlay/` | What it is |
| --- | --- |
| `chrome/app/` | `crest_user_data_dir.h` and `crest_profile_adoption.h`: the user data directory, resolved before Chromium loads, and adoption of `Crest-*` profiles |
| `chrome/browser/ui/crest/crest_engine_binding.*` | The engine binding: takes the core's commands and reports engine events |
| `chrome/browser/ui/crest/crest_engine_*.{h,cc}` | One area of the binding each: pages, browsers, profiles, content, documents, downloads, extensions, Web Store, infobars, inspector, media, notifications, prompts, screen sharing, tab groups, agent |
| `chrome/browser/ui/crest/crest_browser_window.*` | The `BrowserWindow` adapted from Mori, with explicit window assignments |
| `chrome/browser/ui/crest/crest_chrome_host.mm` | The Mac host: extension popups and shortcuts |
| `chrome/browser/ui/crest/crest_*_hooks.h`, `crest_*_prompt.h` | Hooks the patch calls and the permission and extension prompts |

The install also copies `Apple/CrestChromiumHost.h` and the engine contract
headers into `chrome/browser/ui/crest/`. The binding reports what Chromium did
and never decides browser rules; a Space is one profile and a private window a
fresh incognito profile (`Documentation/Architecture/EngineAbstractionCompletion.md`,
"Ownership"). The Crest window is selected only with `--crest-control-plane`,
and the overlay installs only after the baseline build has stopped
(`README.md`, "Native Crest host overlay").

## Read next

`README.md` ("Releasing"), `ForkMaintenance.md`, and
`Documentation/Architecture/EngineAbstractionCompletion.md`.
