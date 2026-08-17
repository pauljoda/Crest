import SwiftUI

struct BrowserRootBackdrop: View, BrowserChromeAnimating {
    let space: BrowserSpace?
    let transparencyIsEnabled: Bool
    let transparencyStrength: Double
    let isWindowFocused: Bool

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(backdropMaterialOpacity)
            BrowserWindowAtmosphere(space: space)
                .opacity(baseLayerOpacity)
        }
        .ignoresSafeArea()
        .animation(
            chromeAnimation(CrestMotion.windowBackdrop),
            value: baseLayerOpacity
        )
        .animation(
            chromeAnimation(CrestMotion.windowBackdrop),
            value: backdropMaterialOpacity
        )
    }

    private var baseLayerOpacity: Double {
        BrowserWindowTransparencyPolicy.baseLayerOpacity(
            isEnabled: transparencyIsEnabled && !reduceTransparency,
            strength: transparencyStrength,
            isWindowFocused: isWindowFocused
        )
    }

    private var backdropMaterialOpacity: Double {
        BrowserWindowTransparencyPolicy.backdropMaterialOpacity(
            isEnabled: transparencyIsEnabled && !reduceTransparency,
            isWindowFocused: isWindowFocused
        )
    }
}
