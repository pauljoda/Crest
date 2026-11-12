import SwiftUI

/// One Space's crest as the switcher draws it, or its dot when Space icons
/// are dots.
///
/// The shared artwork preserves the crest's original colors and layered badge
/// in both the compact desktop track and the expanded touch segments.
struct BrowserSpacePickerIcon: View {
    let space: BrowserSpaceIdentity
    let metrics: BrowserSpacePickerMetrics
    /// The Spaces the switcher shades its dots among, or nil to draw the
    /// Space's crest.
    var dots: BrowserSpaceDot.Field? = nil

    var body: some View {
        if let dots {
            BrowserSpaceDot(
                spaceID: space.id, field: dots, isLocked: space.requiresAuthentication,
                scale: metrics.iconSize / BrowserSpacePickerMetrics.pointer.iconSize
            )
            // The dot takes its whole segment, so a tab drops on it easily.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .transition(.opacity)
        } else {
            BrowserSpaceSymbolArtwork(
                identity: space,
                size: metrics.iconSize,
                lockSize: metrics.lockSize
            )
            .padding(metrics.iconPadding)
            .transition(.opacity)
        }
    }
}
