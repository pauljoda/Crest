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

#Preview("Command Palette Scrim") {
    ZStack {
        CrestBrandTheme.canvas
        Label("Background Content", systemImage: "safari")
            .font(.title2)
        BrowserCommandPaletteScrim(dismiss: {})
    }
    .frame(width: 520, height: 320)
}
