import SwiftUI

/// Crest's mark: the Crest banner cut from paper three times and stacked on
/// an ink tile, butter in front, coral behind it and sky at the back, under a
/// rim one device pixel wide. Large, each banner casts a soft shadow on the
/// one behind; small, the mark is flat and the front two banners carry an
/// ink keyline instead. Depth comes from the layers, never from gloss.
struct CrestStartPageMark: View {
    // MARK: - Types

    /// One paper layer of the mark: its color, how far down the tile it sits
    /// and the shadow it casts, on the mark's 64-point grid.
    private struct Layer: Identifiable {
        let id: Int
        let color: Color
        let drop: CGFloat
        let shadowOffset: CGFloat
        let shadowRadius: CGFloat
        let shadowOpacity: Double
        /// Whether the layer carries the ink keyline when the mark is small.
        let keyline: Bool
    }

    // MARK: - Static Variables

    /// Back to front.
    private static let layers = [
        Layer(
            id: 0, color: CrestBrandPalette.sky, drop: 18, shadowOffset: 1.6, shadowRadius: 3.2, shadowOpacity: 0.3,
            keyline: false),
        Layer(
            id: 1, color: CrestBrandPalette.coral, drop: 9, shadowOffset: 2.2, shadowRadius: 2.6, shadowOpacity: 0.42,
            keyline: true),
        Layer(
            id: 2, color: CrestBrandPalette.butter, drop: 0, shadowOffset: 2.2, shadowRadius: 2.6, shadowOpacity: 0.42,
            keyline: true),
    ]

    // MARK: - Variables

    @Environment(\.displayScale) private var displayScale

    // MARK: - Actions - Drawing

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let unit = side / CrestStartPageMarkMetrics.grid
            let isFlat = side <= CrestStartPageMarkMetrics.flatSide
            let tile = RoundedRectangle(
                cornerRadius: side * CrestStartPageMarkMetrics.cornerRadiusRatio, style: .continuous)
            ZStack {
                tile.fill(CrestBrandPalette.ink)
                ForEach(Self.layers) { layer in
                    banner(layer, unit: unit, isFlat: isFlat)
                        .offset(y: layer.drop * unit)
                }
                tile.strokeBorder(
                    .white.opacity(CrestStartPageMarkMetrics.borderOpacity), lineWidth: 1 / displayScale)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    /// One banner: shadowed when the mark is large, keylined when it is
    /// small, the keyline drawn under the fill so only its outer half shows.
    @ViewBuilder
    private func banner(_ layer: Layer, unit: CGFloat, isFlat: Bool) -> some View {
        if isFlat {
            ZStack {
                if layer.keyline {
                    CrestMarkBannerShape().stroke(
                        CrestBrandPalette.ink,
                        style: StrokeStyle(
                            lineWidth: CrestStartPageMarkMetrics.keylineWidth * unit, lineJoin: .round))
                }
                CrestMarkBannerShape().fill(layer.color)
            }
        } else {
            CrestMarkBannerShape()
                .fill(layer.color)
                .shadow(
                    color: CrestBrandPalette.markShadow.opacity(layer.shadowOpacity),
                    radius: layer.shadowRadius * unit, y: layer.shadowOffset * unit
                )
        }
    }
}

#if DEBUG
    #Preview("Component") {
        HStack(spacing: 24) {
            CrestStartPageMark().frame(width: 128, height: 128)
            CrestStartPageMark().frame(width: 32, height: 32)
        }
        .padding()
    }
#endif
