import SwiftUI

/// The shade the edge of setup's sheet of paper casts on the room beside it:
/// a soft band just past the edge, drawn as a gradient, so it moves with the
/// sheet for nothing, where a shadow worked out from the sheet would be
/// blurred again on every frame it slides.
struct BrowserSetupSheetEdge: View {
    // MARK: - Actions - Drawing

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: CrestBrandPalette.ink.opacity(BrowserSetupSheetEdgeMetrics.shade), location: 0),
                .init(
                    color: CrestBrandPalette.ink.opacity(BrowserSetupSheetEdgeMetrics.shade * 0.35),
                    location: 0.35),
                .init(color: CrestBrandPalette.ink.opacity(0), location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(width: BrowserSetupSheetEdgeMetrics.width)
        .offset(x: BrowserSetupSheetEdgeMetrics.width)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum BrowserSetupSheetEdgeMetrics {
    static let width: CGFloat = 22
    static let shade = 0.22
}
