import SwiftUI

/// The translation bar's controls: the design system's chrome surface, at
/// rest on its quiet fill where controls group, with the bar's own press
/// motion. The bar's one prominent action draws its glyph and title in the
/// accent's text color, which keeps text contrast.
struct BrowserTranslationToolbarControlStyle: ButtonStyle {
    // MARK: - Variables

    var isGrouped = false
    var isProminent = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Actions - Drawing

    func makeBody(configuration: Configuration) -> some View {
        CrestChromeButtonStyle(
            controlSize: nil,
            showsRestingFill: isGrouped,
            tint: isProminent ? CrestBrandTheme.accentText : nil
        )
        .makeBody(configuration: configuration)
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
        .animation(reduceMotion ? nil : CrestMotion.developerPress, value: configuration.isPressed)
    }
}
