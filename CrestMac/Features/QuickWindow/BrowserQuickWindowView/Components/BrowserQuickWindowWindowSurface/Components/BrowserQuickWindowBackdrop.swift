import SwiftUI

struct BrowserQuickWindowBackdrop: View {
    let space: BrowserSpace?
    let opacity: Double
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            BrowserWindowAtmosphere(space: space)
                .opacity(opacity)
        }
        .ignoresSafeArea()
        .animation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.windowBackdrop,
                reduceMotion: reduceMotion
            ),
            value: opacity
        )
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserQuickWindowBackdrop(
            space: BrowserSpaceBrandingPreviewFixture.simpleSpace, opacity: 0.8, reduceMotion: true
        ).frame(width: 540, height: 360)
    }
#endif
