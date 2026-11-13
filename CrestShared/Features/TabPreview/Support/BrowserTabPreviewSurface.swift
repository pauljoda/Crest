import SwiftUI

/// The surface every sidebar preview card floats on: Liquid Glass, as for
/// everything that floats over the page, with the soft shadow of Crest's
/// notices. A card holds what it shows the sidebar's inset from its sides,
/// and its corners run parallel to the corners of the sidebar's layers
/// inside it.
struct BrowserTabPreviewSurface: ViewModifier {
    // MARK: - Static Variables

    /// How wide a card is, unless a held one takes more of a narrow window.
    nonisolated static let width: CGFloat = 280
    /// How far a card holds what it shows from its sides.
    static let padding = BrowserSidebarMetrics.layerInset

    // MARK: - Variables

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.browserTabPreviewCardWidth) private var width

    // MARK: - Actions - Presentation

    func body(content: Content) -> some View {
        content
            .frame(width: width, alignment: .leading)
            .glassEffect(
                .regular, in: .rect(cornerRadius: BrowserSidebarMetrics.layerCornerRadius() + Self.padding)
            )
            .shadow(
                color: .black.opacity(reduceTransparency ? 0 : CrestOpacity.controlShadow),
                radius: 14, y: 6)
    }
}

extension View {
    /// Draws this card on the surface every sidebar preview card floats on.
    func browserTabPreviewSurface() -> some View {
        modifier(BrowserTabPreviewSurface())
    }
}
