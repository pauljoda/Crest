import SwiftUI

/// One extension's side-panel icon at a given size.
///
/// Package artwork is drawn as the extension authored it — the mark's job is to
/// say *which* extension holds the panel, and a tinted silhouette cannot. Only
/// the fallback is a template symbol, because there is no identity left to
/// preserve by then.
struct BrowserTabSidePanelArtwork: View {
    let icon: Image?
    let size: CGFloat

    @ViewBuilder
    var body: some View {
        if let icon {
            icon
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: BrowserTabSidePanelIndicatorMetrics.fallbackSymbol)
                .font(.system(size: size))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}

#Preview {
    HStack(spacing: CrestSpacing.medium) {
        BrowserTabSidePanelArtwork(
            icon: nil,
            size: BrowserTabSidePanelIndicatorMetrics.rowArtworkSize
        )
        BrowserTabSidePanelArtwork(
            icon: Image(systemName: "sparkles"),
            size: BrowserTabSidePanelIndicatorMetrics.rowArtworkSize
        )
    }
    .padding()
}
