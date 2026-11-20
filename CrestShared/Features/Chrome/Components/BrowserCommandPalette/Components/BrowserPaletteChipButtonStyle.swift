import SwiftUI

/// The button a palette chip is: the chip answers the pointer itself, and a
/// press shrinks it as a press does any of Crest's buttons.
struct BrowserPaletteChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(BrowserPaletteChipPress(isPressed: configuration.isPressed))
    }
}

extension ButtonStyle where Self == BrowserPaletteChipButtonStyle {
    /// A palette chip a person can click.
    static var browserPaletteChip: BrowserPaletteChipButtonStyle { BrowserPaletteChipButtonStyle() }
}

private struct BrowserPaletteChipPress: ViewModifier {
    let isPressed: Bool

    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.crestPressFeedback(isPressed: isPressed, isEnabled: isEnabled)
    }
}
