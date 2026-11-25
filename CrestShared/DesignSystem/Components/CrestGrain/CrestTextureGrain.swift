import SwiftUI

/// The grain a Space's sidebar lays over its colors as its texture, which
/// the texture slider previews: specks in soft light, or, while the system
/// reduces transparency and the colors under it are opaque, a fine film
/// grain laid on as it is, which soft light would all but hide there.
struct CrestTextureGrain: View {
    // MARK: - Variables

    let reducesTransparency: Bool

    // MARK: - Actions - Drawing

    var body: some View {
        if reducesTransparency {
            CrestFilmGrain()
        } else {
            CrestGrain()
                .blendMode(.softLight)
        }
    }
}
