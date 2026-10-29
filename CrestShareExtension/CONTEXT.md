# CrestShareExtension

The iPhone and iPad share-sheet entry for Crest. It reads the web link
another app shared and hands it to Crest by opening a `crest://open` URL, or
shows a short notice when it cannot.

## Goal

Get a shared link into Crest with no UI beyond what the failure case needs.

## Contents

| File | What it is |
| --- | --- |
| `CrestShareViewController.swift` | The extension's principal view controller; opens the `crest://open` URL |
| `CrestShareModel.swift` | Reads the shared item and tracks whether hand-off succeeded |
| `CrestShareView.swift` | The SwiftUI notice shown when hand-off fails |
| `Info.plist` | Extension point and activation rules (`INFOPLIST_FILE` in `project.yml`) |

## Depends on

`CrestMobile/Infrastructure/BrowserLinkSharing/` and
`CrestShared/Resources/Localizable.xcstrings`, compiled into the same target
(`project.yml`). Embedded by `CrestMobile`. Never the core.

## Rules

- Shared-link parsing lives in `CrestMobile/Infrastructure/BrowserLinkSharing/`, which the app uses too; change it there (`project.yml`, `CrestShareExtension` comment).
- Never compile the core into the extension; its memory budget cannot hold it (`project.yml`, `CrestShareExtension` comment).
- Copy is short and native, through `String(localized:)` (skill, "Writing").
- A regenerated `CrestShared/Resources/Localizable.xcstrings` belongs to the change that caused it (`AGENTS.md`, "Generated localization catalog").

## Read next

`CrestMobile/CONTEXT.md` and `CrestMobileTests/BrowserSharedLinkTests.swift`.
