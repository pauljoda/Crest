import SwiftUI

struct BrowserCommandPaletteScrim: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.browserCommandPaletteTransitionPhase) private var transitionPhase
    @AppStorage(BrowserCommandPaletteScrimPreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var dimsPage = BrowserCommandPaletteScrimPreference.defaultValue

    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            Color.black.opacity(
                dimsPage
                    ? BrowserCommandPaletteMetrics.scrimOpacity.scrimOpacity(reduceTransparency: reduceTransparency)
                    : 0
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .ignoresSafeArea(.container, edges: .all)
        .opacity(transitionPhase.isIdentity ? 1 : 0)
        .accessibilityHidden(true)
    }
}
