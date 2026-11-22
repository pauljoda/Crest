import SwiftUI

/// A Space's crest or icon at `size`, as `branding` and `symbol` draw it,
/// for the stage of a Space's appearance.
struct BrowserCrestStudioMark: View {
    let branding: SpaceBranding
    let symbol: String
    var size: CGFloat

    var body: some View {
        BrowserSpaceIdentityIcon(
            identity: BrowserSpaceAppearance.studioSample.identity.wearing(
                branding, symbol: symbol, name: BrowserSpaceAppearance.studioSample.identity.name),
            size: size)
    }
}

extension BrowserSpaceAppearance {
    /// The Space the stage dresses in the look being edited: the showcase's
    /// first Space.
    @MainActor static let studioSample = BrowserSpaceAppearance(
        space: SpaceModel.detached(SessionState.Seed.showcase.spaces[0]))
}
