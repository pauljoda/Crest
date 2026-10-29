# Resources

The resources both apps bundle: the string catalog, the privacy manifest, the
app icon and its palette variants, the heraldry used for Space crests, and the
logos and catalogs that settings and pickers show. Generated catalogs are
written by scripts in `Scripts/`; third-party artwork has its source recorded
beside it or in `Documentation/`.

## Goal

One copy of every shared string and asset, each traceable to a source or a
generator.

## Contents

| Path | What it is |
| --- | --- |
| `Localizable.xcstrings` | The string catalog; Xcode regenerates it from `String(localized:)` |
| `PrivacyInfo.xcprivacy` | The app's privacy manifest |
| `CrestIcon/` | Icon Composer icons (`Crest.icon` and palette variants); `Sources/` SVG layers and `Validation/` renders are excluded from targets in `project.yml` |
| `AppIconPreviews.xcassets` | Dock and picker previews of each app icon variant |
| `CrestHeraldry.xcassets` | Heraldic charges for Space crests; credits in `HeraldicArtworkCredits.txt` |
| `GettingStartedLogos.xcassets` | Website logos for the Getting Started practice pages |
| `SearchProviderLogos.xcassets` | Search provider marks |
| `AboutBrandIcons.xcassets` | Brand icons the About pane links with |
| `EmojiCatalog.json` | The emoji picker catalog, from Unicode test data |
| `SFSymbolNames.txt`, `SFSymbolCatalog-LICENSE.txt` | The name-only SF Symbol catalog for the symbol picker and its licence |
| `HeraldicArtworkCredits.txt` | Attribution for the heraldic artwork |

## Depends on

Nothing at runtime. Generators: `Scripts/generate-emoji-catalog.py`,
`Scripts/update-sf-symbol-catalog.py`, `Scripts/generate-app-icon-palettes.py`.
`Scripts/validate-identity.sh` requires `CrestIcon/Crest.icon`. Consumed by
every target that includes `CrestShared`; `CrestShareExtension` takes only
`Localizable.xcstrings` (`project.yml`).

## Rules

- A regenerated `Localizable.xcstrings` belongs to the change that caused it (`AGENTS.md`, "Generated localization catalog").
- User-facing strings go through `String(localized:)` and the catalog, short and platform-native (skill, "Writing").
- Target membership is set in `project.yml`, never in the Xcode project (skill, "Pull request").

## Read next

`Documentation/GettingStartedLogos.md`, `Documentation/SearchProviderLogos.md`,
and the generator script for the catalog being changed.
