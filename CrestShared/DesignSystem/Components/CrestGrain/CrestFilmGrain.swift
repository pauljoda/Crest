import SwiftUI

/// A fine film grain, light and dark at every pixel, the same wherever it is
/// drawn. Laid on as it is, it stays visible over opaque colors, where the
/// soft light ``CrestGrain`` uses all but vanishes.
///
/// The grain is drawn once, into a tile at the screen's scale, which it
/// repeats across whatever it covers, as ``CrestGrain`` does.
struct CrestFilmGrain: View {
    // MARK: - Variables

    @Environment(\.displayScale) private var displayScale

    // MARK: - Actions - Drawing

    var body: some View {
        Group {
            if let tile = CrestFilmGrainTile.image(scale: displayScale) {
                Image(decorative: tile, scale: displayScale)
                    .resizable(resizingMode: .tile)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
