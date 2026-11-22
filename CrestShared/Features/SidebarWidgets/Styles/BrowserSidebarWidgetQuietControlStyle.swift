import SwiftUI

/// A glyph on a widget card: the design system's round chrome control at the
/// card's glyph size, in its place within a full hit target, such as the
/// top trailing corner for a card's hide control.
struct BrowserSidebarWidgetQuietControlStyle: ButtonStyle {
    // MARK: - Variables

    var alignment: Alignment = .center

    // MARK: - Actions - Drawing

    func makeBody(configuration: Configuration) -> some View {
        CrestChromeButtonStyle.circle(diameter: BrowserSidebarWidgetDeckStyle.quietControlDiameter)
            .makeBody(configuration: configuration)
            .font(BrowserSidebarWidgetDeckStyle.quietControlSymbolFont)
            .frame(
                width: BrowserSidebarWidgetDeckStyle.quietControlHitTarget,
                height: BrowserSidebarWidgetDeckStyle.quietControlHitTarget,
                alignment: alignment
            )
            .contentShape(.rect)
    }
}
