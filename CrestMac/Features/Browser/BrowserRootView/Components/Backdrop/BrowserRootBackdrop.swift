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
            // Preserve coverage while colors change. Replacing this whole
            // layer for a Space ID briefly exposes the material during a fade.
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
        .animation(
            chromeAnimation(CrestMotion.windowBackdrop),
            value: space?.branding
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
