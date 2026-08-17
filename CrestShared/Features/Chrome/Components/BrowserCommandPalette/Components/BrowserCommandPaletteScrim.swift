import SwiftUI

struct BrowserCommandPaletteScrim: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            Color.black.opacity(
                BrowserVisualAccessibilityPolicy.scrimOpacity(
                    BrowserCommandPaletteMetrics.scrimOpacity,
                    reduceTransparency: reduceTransparency
                )
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .ignoresSafeArea(.container, edges: .all)
        .accessibilityHidden(true)
    }
}
