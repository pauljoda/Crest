import SwiftUI

/// A tile of Crest's paper in one color with a solid glyph on it, for
/// navigation, settings and feature identity: flat, and when it casts a
/// shadow, a paper one in ink, as a tile cut and laid on the page.
struct CrestIconTile: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 30
    var symbolSize: CGFloat = 14
    var cornerRadius: CGFloat = CrestRadius.compact
    var castsShadow = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: symbolSize, weight: .semibold))
            .browserReadableForeground(over: color)
            .frame(width: size, height: size)
            .background(color, in: .rect(cornerRadius: cornerRadius))
            .shadow(
                color: CrestBrandPalette.ink.opacity(
                    castsShadow && !reduceTransparency ? CrestIconTileMetrics.shadow : 0),
                radius: castsShadow ? CrestIconTileMetrics.shadowRadius : 0,
                y: castsShadow ? CrestIconTileMetrics.shadowDrop : 0
            )
    }
}

enum CrestIconTileMetrics {
    /// The paper shadow a tile casts on the page under it.
    static let shadow = 0.24
    static let shadowRadius: CGFloat = 1.2
    static let shadowDrop: CGFloat = 1
}

#if DEBUG
    #Preview("Sizes and colors") {
        HStack(spacing: 20) {
            CrestIconTile(systemImage: "gearshape.fill", color: .indigo)
            CrestIconTile(systemImage: "lock.shield.fill", color: .green, castsShadow: true)
            CrestIconTile(systemImage: "square.grid.2x2.fill", color: .orange, size: 48, symbolSize: 24)
        }.padding()
    }
#endif
