import SwiftUI

/// One Space's crest as the switcher draws it.
///
/// It goes through `BrowserSpaceSymbolArtwork` rather than rendering the
/// symbol directly, because both arrangements hand their segments to a native
/// control — a segmented picker on one side, a button track on the other — and
/// those flatten a layered crest unless it arrives as a single original-color
/// image.
struct BrowserSpacePickerIcon: View {
    let space: BrowserSpace
    let metrics: BrowserSpacePickerMetrics

    var body: some View {
        BrowserSpaceSymbolArtwork(
            space: space,
            size: metrics.iconSize,
            lockSize: metrics.lockSize
        )
        .padding(metrics.iconPadding)
    }
}
