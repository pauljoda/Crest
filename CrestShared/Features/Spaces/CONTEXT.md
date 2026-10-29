# CrestShared/Features/Spaces

How a Space looks and is picked: its branding (banner, crest, identity
artwork, textures), the Crest Studio that composes a crest step by step
(`Components/Forge/`), the branding editor, the inline name field, and the
Space selectors (menu picker, chip rail, icon picker) other features reuse.

## Goal

One Space identity drawn the same wherever it appears, edited in one studio
on every shell.

## Contents

| Path | What it is |
| --- | --- |
| `Components/BrowserSpaceBranding/` | Banner background and the banner, crest, identity and shape views |
| `Components/BrowserSpaceBrandingEditor/` | The branding editor: field, pattern and preview sections, and the Crest Studio pickers (`Studio/`) |
| `Components/Forge/` | `BrowserCrestForge`, the Crest Studio stage beside the live sidebar |
| `Components/CrestSpaceSelector/` | Space menu picker, chip rail and icon picker |
| `Components/` (files) | Inline Space name, the customization picker, the touch appearance workspace for setup |
| `Models/` | Studio steps and branding values such as gradient-angle direction |
| `Services/BrowserSpaceBranding/` | Rendering a Space symbol to artwork |
| `Support/` | Heraldry and branding presentation, tab icon accent colors, `SpaceModel` tab lists, the branding preview fixture |

## Depends on

The core's `SpaceModel` and branding values through
`CrestShared/Infrastructure/Core/`, `DesignSystem/`, `Sidebar/` (switcher
layout), `Settings/` (appearance previews and pane chrome). Used by
`Sidebar/` (header and switcher), `Settings/` (Space sections),
`Onboarding/` (manual setup), `Credentials/` and `TransientBrowsing/` (Space
identity), `Browser/` (banner backdrop), the Space editors in
`CrestMac/Features/Settings/` and `CrestMobile/Features/Settings/`, and
`CrestMac/Features/Onboarding/`.

## Rules

- Spaces live in the core; Swift edits them through intents (skill, "Architecture").
- A Space is the privacy boundary; what it owns is listed in `Documentation/ARCHITECTURE.md`, "Space isolation".
- Colours come from the Crest tokens and template house palettes, never system rainbow colours (skill, "Windows and UI").
- Previews reuse the feature's fixture, `CrestShared/Features/Spaces/Support/BrowserSpaceBrandingPreviewFixture.swift`, with fixed identities and dates (`Documentation/RepositoryGuardrails.md`, "Feature organization").

## Read next

`Documentation/ARCHITECTURE.md` ("Space isolation"), then `Sidebar/` for
where a Space is shown and `Settings/` for where it is edited.
