# CrestEngines/Chromium/Overlay

C++ and Objective-C++ sources added to the Chromium source tree, mirrored at
the paths they take there. They hold Chromium's engine binding (portable C++
that implements the engine contract and reports straight to the core), the
`BrowserWindow` that puts Crest's SwiftUI chrome behind Chrome's window
interface, and the Mac host glue. `Scripts/control-plane/apply-chromium-host.py`
copies this tree into the source after `../Patches/native-host.patch` applies.

## Goal

Let Chrome's own `Browser`, tab model and extension system drive Crest's UI
and report to Crest's core, behind the same engine contract as WebKit.

## Contents

| Path | What it is |
| --- | --- |
| `chrome/app/` | `crest_user_data_dir.h` and `crest_profile_adoption.h`: the product's user data directory, resolved before Chromium loads, and adoption of `Crest-*` profiles from the old directory |
| `chrome/browser/ui/crest/crest_engine_binding.*` | The engine binding: takes the core's commands through its table and reports engine events |
| `chrome/browser/ui/crest/crest_engine_*.{h,cc}` | One area of the binding each: pages, browsers, profiles, content, documents, downloads, extensions, the Chrome Web Store, infobars, inspector, media, notifications, prompts, screen sharing, tab groups, agent |
| `chrome/browser/ui/crest/crest_browser_window.*` | The `BrowserWindow` adapted from Mori, with explicit window assignments |
| `chrome/browser/ui/crest/crest_chrome_host.mm` | The Mac host: extension popups and shortcuts for the platform |
| `chrome/browser/ui/crest/crest_*_hooks.h`, `crest_*_prompt.h` | Hooks the patch calls (isolated worlds, downloads) and the permission and extension prompts |

At install time the script also copies `../Apple/CrestChromiumHost.h` and the
engine contract headers from `CrestContracts/include` into
`chrome/browser/ui/crest/`; they are not kept here.

## Depends on

The pinned upstream source (`../source.lock.json`), `../Patches/` and the
reviewed hashes in `../host-inputs.json`, the generated C++ engine codec and C
ABI in `CrestContracts/include`, and `../Apple/CrestChromiumHost.h`. Configured
and built by the control-plane scripts (`Scripts/control-plane/configure-chromium.py`,
`build-chromium-baseline.py`).

## Rules

- Everything here is an engine input: a change needs a maintainer-published engine; say so in the pull request (`AGENTS.md`, "Published Chromium engine").
- The binding reports what Chromium did and never decides browser rules (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Ownership").
- The Crest window is selected only with `--crest-control-plane`; the default baseline stays stock (`../README.md`, "Native Crest host overlay").
- A Space is one profile and a private window a fresh incognito profile (`Documentation/Architecture/EngineAbstractionCompletion.md`, "Ownership").
- Adapted Mori code keeps its provenance and retained license in `../ThirdParty/` (`../README.md`, "Native Crest host overlay").
- Install the overlay only after the baseline build has stopped (`../README.md`, "Native Crest host overlay"; enforced by `apply-chromium-host.py`).

## Read next

`../README.md` ("Native Crest host overlay", "Releasing"),
`Documentation/Architecture/CoreArchitecture.md` ("Engines"), then
`chrome/browser/ui/crest/crest_engine_binding.h`.
