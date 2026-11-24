import SwiftUI

/// The surface every sidebar preview card floats on: Crest's flyout surface,
/// as for everything that floats over the page, with the soft shadow of
/// Crest's notices. A card holds what it shows the sidebar's inset from its
/// sides, and its corners run parallel to the corners of the sidebar's layers
/// inside it.
///
/// What the card shows reads in the label colors of that surface, whichever
/// the Space's text, the window's appearance or the page behind would choose,
/// so its text never draws light on light or dark on dark.
struct BrowserTabPreviewSurface: ViewModifier {
    // MARK: - Static Variables

    /// How wide a card is, unless a held one takes more of a narrow window.
    nonisolated static let width: CGFloat = 280
    /// How far a card holds what it shows from its sides.
    static let padding = BrowserSidebarMetrics.layerInset

    // MARK: - Variables

    @Environment(\.browserTabPreviewCardWidth) private var width

    // MARK: - Actions - Presentation

    func body(content: Content) -> some View {
        content
            // The label color itself, not the Space ink a hierarchical style
            // would take its levels from.
            .foregroundStyle(Color.primary)
            .environment(\.spaceChromeForeground, nil)
            .frame(width: width, alignment: .leading)
            .crestFloatingFlyoutStyle(in: .rect(cornerRadius: BrowserSidebarMetrics.layerCornerRadius() + Self.padding))
            .crestElevation(.panel)
    }
}

extension View {
    /// Draws this card on the surface every sidebar preview card floats on.
    func browserTabPreviewSurface() -> some View {
        modifier(BrowserTabPreviewSurface())
    }
}
