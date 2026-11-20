import SwiftUI

/// The edge a palette card floats on over the page: a warm hairline just
/// inside its outline and a soft shadow cast outside it alone, so the
/// material never shows its own shadow through it.
struct BrowserCommandPaletteCardEdge: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .overlay {
                shape.strokeBorder(CrestBrandTheme.line, lineWidth: CrestLayout.hairline)
                    .allowsHitTesting(false)
            }
            .background {
                CrestLiftedSurfaceShadow(
                    cornerRadius: cornerRadius,
                    opacity: BrowserCommandPaletteMetrics.cardShadowOpacity,
                    radius: BrowserCommandPaletteMetrics.cardShadowRadius,
                    yOffset: BrowserCommandPaletteMetrics.cardShadowYOffset)
            }
    }
}
