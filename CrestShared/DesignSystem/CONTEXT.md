# DesignSystem

Crest's shared SwiftUI vocabulary: tokens for colour, type, spacing, radius,
motion and materials; the canonical controls (buttons, fields, form and
setting rows, selectable cards, interactive surfaces); accessibility
identifiers and reduced-motion helpers; and collection animation. Features on
both platforms build from these instead of drawing their own.

## Goal

Every control and fill looks and responds the same everywhere, with hover and
pressed states supplied by the system rather than reinvented per feature.

## Contents

| Path | What it is |
| --- | --- |
| `Tokens/` | `CrestColor` (with brand palette and Space colour schemes), `CrestTypography`, `CrestSpacing`, `CrestRadius`, `CrestLayout`, `CrestMotion`, `CrestOpacity`, `CrestSurfaceMaterial`, `CrestBrandTheme` |
| `Components/CrestInteractiveSurface/` | `crestInteractiveSurface`, `CrestChromeButtonStyle` and the surface layer for rows, tiles and glyph buttons |
| `Components/CrestButtonStyle/` | The one `ButtonStyle` Crest draws: roles, metrics, press feedback, surface |
| `Components/CrestTextField/` | The single text-field treatment and focus ring |
| `Components/CrestFormRow/` | Native form rows: labels, control and action rows, footnotes, disclosure chevron |
| `Components/CrestSettingRow/` | A setting's row, group, slider, section heading and stored value |
| `Components/CrestSettingsPresentation/` | Settings layout metrics, destination labels and the settings-form modifier |
| `Components/BrowserSettingsControls/` | Settings icon and labeled action button styles |
| `Components/CrestSelectableCard/` | A keyboard-reachable choice card with shared selection states |
| `Components/BrowserReloadControl/` | The shared reload control and its feedback icon |
| `Components/BrowserRootContentSurface/` | The stable root frame around browser content |
| `Components/*.swift` | Chrome symbol label, page toolbar host, icon tile, shortcut command labels, and the `#if DEBUG` `CrestControlsGallery` |
| `Accessibility/` | Stable accessibility identifiers, readable foregrounds, Reduce Motion and Reduce Transparency helpers |
| `Animations/` | `CrestCollectionMotion`: collection changes that honor Reduce Motion |
| `Modifiers/` | `CrestViewModifiers`, shared view modifiers |

## Depends on

SwiftUI and CoreGraphics; `Domain/` values and core contract types such as `SpaceBranding` and `ShortcutCommand`.
Consumed by `Features/` and the platform shells.

## Rules

- Search here before writing a new fill or control; reuse `crestInteractiveSurface`, `CrestChromeButtonStyle` and the tokens, with no ad-hoc opacity fills or system rainbow colours (skill, "Windows and UI").
- Every interactive control has hover and pressed states from the system (skill, "Windows and UI").
- Informational feedback uses the notice capsule, not a modal (skill, "Windows and UI").
- Previews sit beside the component that owns editable UI, are deterministic, and live in `#if DEBUG` (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- Components are canonical in `CrestShared`; a platform difference is a capability bit, shell input, optional action or accessory slot, never a fork or a device identity (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- No tests for token values, layout numbers, accessibility identifier strings or previews (`Documentation/RepositoryGuardrails.md`, "Feature organization").
- No `AnyView`, and follow the Xcode 27 `@State` rules `Scripts/check-architecture.py` checks (`Documentation/RepositoryGuardrails.md`, "Architecture and Xcode 27 compatibility").

## Read next

`Components/CrestControlsGallery.swift` for every control on one canvas, then
the component folder being changed.
