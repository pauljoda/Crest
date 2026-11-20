import SwiftUI

/// A fine film grain of light and dark specks, the same wherever it is drawn,
/// which a Space's sidebar lays over its colors as its texture and a color
/// picker previews.
///
/// The specks are drawn once, into a tile at the screen's scale, which the
/// grain repeats across whatever it covers. Moving, clipping or resizing the
/// grain only shows more or less of the tile, so a sheet sliding or a window
/// growing over it never draws the specks again.
struct CrestGrain: View {
    // MARK: - Variables

    /// How many specks lie on each square point; the large sheets setup
    /// lies on take fewer.
    var density = CrestGrainMetrics.density

    @Environment(\.displayScale) private var displayScale

    // MARK: - Actions - Drawing

    var body: some View {
        Group {
            if let tile = CrestGrainTile.image(scale: displayScale, density: density) {
                Image(decorative: tile, scale: displayScale)
                    .resizable(resizingMode: .tile)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum CrestGrainMetrics {
    /// How strongly a full grain lies over the colors under it, and while
    /// the system reduces transparency.
    static let fullOpacity = 0.38
    static let reducedTransparencyOpacity = 0.24
    /// One speck to every 24 square points, as a sidebar has always had.
    static let density = 1.0 / 24
}
