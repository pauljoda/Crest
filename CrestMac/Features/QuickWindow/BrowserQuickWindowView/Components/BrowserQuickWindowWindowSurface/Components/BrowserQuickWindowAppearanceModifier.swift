import SwiftUI

struct BrowserQuickWindowAppearanceModifier: ViewModifier {
    let model: BrowserQuickWindowModel

    @Environment(BrowserWindowTransparencyStore.self)
    private var windowTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isWindowFocused = true

    func body(content: Content) -> some View {
        content
            .background {
                BrowserQuickWindowBackdrop(
                    space: model.space,
                    opacity: windowBaseLayerOpacity,
                    reduceMotion: reduceMotion
                )
            }
            .overlay(alignment: .topLeading) {
                BrowserWindowTransparencyBridge(
                    isEnabled: windowTransparency.isEnabled
                        && !reduceTransparency,
                    isWindowFocused: $isWindowFocused
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }

    private var windowBaseLayerOpacity: Double {
        BrowserWindowTransparencyPolicy.baseLayerOpacity(
            isEnabled: windowTransparency.isEnabled && !reduceTransparency,
            strength: windowTransparency.strength,
            isWindowFocused: isWindowFocused
        )
    }
}
