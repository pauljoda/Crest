import SwiftUI

/// A cached grain tile repeated at the display's scale.
struct CrestGrain: View {
    // MARK: - Types

    enum Style: Hashable {
        case fine
        case speckled(density: Double = CrestGrainMetrics.density)
    }

    // MARK: - Variables

    var style: Style = .speckled()

    @Environment(\.displayScale) private var displayScale

    // MARK: - Actions - Drawing

    var body: some View {
        Group {
            if let tile = CrestGrainTile.image(scale: displayScale, style: style) {
                Image(decorative: tile, scale: displayScale)
                    .resizable(resizingMode: .tile)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum CrestGrainMetrics {
    /// How strongly a full grain lies over the colors under it.
    static let fullOpacity = 0.38
    /// One speck to every 24 square points, as a sidebar has always had.
    static let density = 1.0 / 24
}
