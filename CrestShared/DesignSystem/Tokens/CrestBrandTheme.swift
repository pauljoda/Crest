import SwiftUI

/// The scheme-aware semantic layer over `CrestBrandPalette`.
///
/// `CrestBrandPalette` holds the fixed paper-and-ink identity used by the
/// website and by light-only editorial surfaces. `CrestBrandTheme` names the
/// *roles* those hues play and flips each role between light and dark, so
/// Crest-authored chrome can adopt the brand without hardcoding an appearance.
///
/// Dark variants keep the light hue and lift luminance only as far as legibility
/// demands: cream gives way to cinder, the warm near-black, and paper's
/// surface to charcoal, so dark grounds read in black and white rather than
/// Crest's blues, and Crest blue is lifted so it stays readable on cinder
/// without reading as a different colour. Every pair below clears WCAG AA for text (4.5:1) or
/// non-text (3:1) in both schemes.
enum CrestBrandTheme {
    // MARK: - Static Variables

    // Component pairs

    /// Crest blue, the color of anything a person can press or select, lifted
    /// for dark: the same hue with enough luminance to sit on cinder.
    static let accentLightComponents = CrestBrandPalette.crestBlueComponents
    static let accentDarkComponents = CrestColorComponents(red: 79, green: 142, blue: 224)

    /// The accent when it is *text* rather than a tint.
    ///
    /// `accent` is scoped to the 3:1 non-text minimum, which is all a fill, a stroke,
    /// or a glyph needs. A text-only control — `CrestButtonStyle`'s `.tertiary` and
    /// `.destructive` roles, or a selected palette row's action — is text, and has to
    /// clear 4.5:1 against `canvas`, `surface` and a selected row's accent wash. In
    /// light that takes Crest blue a shade deeper (about 5.3:1 on the wash); on cinder
    /// it is lifted further than the tint.
    static let accentTextLightComponents = CrestColorComponents(red: 34, green: 92, blue: 172)
    static let accentTextDarkComponents = CrestColorComponents(red: 122, green: 170, blue: 235)

    /// The fill of the one action that leads on, under white text: Crest blue
    /// in both schemes, which holds that text at about 5.2:1 and still clears
    /// 3:1 against cinder. The lifted `accent` would leave white text short of
    /// 4.5:1 on it.
    static let actionComponents = CrestBrandPalette.crestBlueComponents

    static let canvasLightComponents = CrestBrandPalette.creamComponents
    static let canvasDarkComponents = CrestBrandPalette.cinderComponents

    static let surfaceLightComponents = CrestBrandPalette.paperComponents
    static let surfaceDarkComponents = CrestBrandPalette.charcoalComponents

    /// Small caps labels: gold on cream (4.6:1), butter on cinder.
    static let labelLightComponents = CrestBrandPalette.goldComponents
    static let labelDarkComponents = CrestBrandPalette.butterComponents

    /// The ground under a control's choices, such as a segmented picker's
    /// track: parchment on cream, a wash of paper on cinder.
    static let trackLightComponents = CrestBrandPalette.parchmentComponents
    static let trackDarkComponents = CrestBrandPalette.paperComponents
    static let trackDarkOpacity = 0.08

    static let textDisplayLightComponents = CrestBrandPalette.inkComponents
    static let textDisplayDarkComponents = CrestBrandPalette.paperComponents
    /// Display text held back for supporting copy. Ink at 0.7 keeps 5.4:1 or
    /// more on paper and parchment; paper at 0.6 keeps 6.5:1 or more on
    /// cinder and charcoal.
    static let textSecondaryLightOpacity = 0.7
    static let textSecondaryDarkOpacity = 0.6

    static let lineLightComponents = CrestBrandPalette.hairlineComponents
    static let lineDarkComponents = CrestBrandPalette.paperComponents
    /// The warm hairline on cream; the dark hairline is paper at a fifth,
    /// because paper on cinder loses definition faster than ink on paper.
    static let lineLightOpacity = 1.0
    static let lineDarkOpacity = 0.22

    /// A wash of display ink, faint enough to sit under text without taking
    /// from its contrast.
    static let quietFillLightOpacity = 0.05
    static let quietFillDarkOpacity = 0.08

    // Semantic roles

    /// Brand accent for interactive emphasis and tint.
    static let accent = dynamic(light: accentLightComponents, dark: accentDarkComponents)
    /// The fill of a primary action. See `actionComponents`.
    static let action = dynamic(light: actionComponents, dark: actionComponents)
    /// Brand accent for text-weight controls. See `accentTextLightComponents`.
    static let accentText = dynamic(
        light: accentTextLightComponents,
        dark: accentTextDarkComponents
    )
    /// The page the content sits on: cream in the light, and in the dark the
    /// warm near-black under charcoal panels, never Crest's blues.
    static let canvas = dynamic(light: canvasLightComponents, dark: canvasDarkComponents)
    /// A raised card or panel on the canvas: paper, or charcoal in the dark.
    static let surface = dynamic(light: surfaceLightComponents, dark: surfaceDarkComponents)
    /// A flyout floating over a page or the window: paper in the light,
    /// charcoal in the dark, opaque so nothing behind it shows through.
    static let flyout = dynamic(light: surfaceLightComponents, dark: CrestBrandPalette.charcoalComponents)
    /// Display and body text on `canvas` or `surface`.
    static let textDisplay = dynamic(
        light: textDisplayLightComponents,
        dark: textDisplayDarkComponents
    )
    /// Supporting text beside `textDisplay`: captions, counts, hints and notes.
    static let textSecondary = dynamic(
        light: textDisplayLightComponents,
        lightOpacity: textSecondaryLightOpacity,
        dark: textDisplayDarkComponents,
        darkOpacity: textSecondaryDarkOpacity
    )
    /// Small caps labels over a section or a group.
    static let label = dynamic(light: labelLightComponents, dark: labelDarkComponents)
    /// The ground under a control's choices.
    static let track = dynamic(
        light: trackLightComponents, lightOpacity: 1, dark: trackDarkComponents, darkOpacity: trackDarkOpacity)
    /// Hairline separators and control borders.
    static let line = dynamic(
        light: lineLightComponents,
        lightOpacity: lineLightOpacity,
        dark: lineDarkComponents,
        darkOpacity: lineDarkOpacity
    )
    /// The quiet ground of a panel or control that sits on `canvas` without
    /// rising to `surface`.
    static let quietFill = dynamic(
        light: textDisplayLightComponents,
        lightOpacity: quietFillLightOpacity,
        dark: textDisplayDarkComponents,
        darkOpacity: quietFillDarkOpacity
    )

    // MARK: - Actions - Resolving

    /// The role values as flat colors, for surfaces that already know which
    /// appearance they render in.
    static func accent(_ colorScheme: ColorScheme) -> Color {
        components(accentLightComponents, accentDarkComponents, colorScheme).color
    }

    static func accentText(_ colorScheme: ColorScheme) -> Color {
        components(accentTextLightComponents, accentTextDarkComponents, colorScheme).color
    }

    static func canvas(_ colorScheme: ColorScheme) -> Color {
        components(canvasLightComponents, canvasDarkComponents, colorScheme).color
    }

    static func surface(_ colorScheme: ColorScheme) -> Color {
        components(surfaceLightComponents, surfaceDarkComponents, colorScheme).color
    }

    static func textDisplay(_ colorScheme: ColorScheme) -> Color {
        components(textDisplayLightComponents, textDisplayDarkComponents, colorScheme).color
    }

    static func line(_ colorScheme: ColorScheme) -> Color {
        let base = components(lineLightComponents, lineDarkComponents, colorScheme)
        return base.color.opacity(colorScheme == .dark ? lineDarkOpacity : lineLightOpacity)
    }

    private static func components(
        _ light: CrestColorComponents,
        _ dark: CrestColorComponents,
        _ colorScheme: ColorScheme
    ) -> CrestColorComponents {
        colorScheme == .dark ? dark : light
    }

    // MARK: - Actions - Construction

    private static func dynamic(
        light: CrestColorComponents,
        lightOpacity: Double = 1,
        dark: CrestColorComponents,
        darkOpacity: Double = 1
    ) -> Color {
        CrestPlatformDynamicColor.make(
            light: light,
            lightOpacity: lightOpacity,
            dark: dark,
            darkOpacity: darkOpacity
        )
    }
}
