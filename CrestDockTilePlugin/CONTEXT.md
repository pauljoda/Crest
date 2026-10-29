# CrestDockTilePlugin

The macOS Dock tile plug-in. The Dock loads it to draw Crest's chosen app
icon palette even while Crest is not running, and redraws when the choice or
the system appearance changes.

## Goal

Keep the Dock icon matching the person's palette choice outside the app's
lifetime.

## Contents

| File | What it is |
| --- | --- |
| `CrestDockTilePlugin.swift` | The `NSDockTilePlugIn` principal class: finds the owning app bundle, observes changes, refreshes the tile |

## Depends on

`CrestMac/Features/AppIcon/BrowserMacAppIconAssets.swift` and
`CrestMac/Features/AppIcon/BrowserMacDockTileView.swift`, compiled into the same target (`project.yml`).
Embedded in the Mac app by the `Crest` and `CrestNativeCore` targets; the
Chromium host gets it from `Scripts/control-plane/package-chromium-host.py`.

## Rules

- The icon drawing and its preference keys are shared with the app in `CrestMac/Features/AppIcon/`; change them there (`BrowserMacAppIconAssets.swift` doc comment; `project.yml`).
- Bundled palette icons are generated from the Icon Composer artwork (`Scripts/generate-app-icon-palettes.py`).
- Icon appearance is reviewed in the running app, never tested (skill, "Tests").

## Read next

`CrestMac/Features/AppIcon/` and `Scripts/generate-app-icon-palettes.py`.
