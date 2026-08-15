import SwiftUI

struct BrowserPeekPageCard: View {
    let model: BrowserPeekModel
    let showsInitialLoadingSurface: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool

    var body: some View {
        ZStack {
            BrowserPeekPageContent(
                page: model.page,
                browser: model.browser,
                pages: model.pages,
                wasReleasedForMemoryPressure:
                    model.pageLease?.wasReleasedForMemoryPressure == true,
                restore: model.restorePage
            )
            if showsInitialLoadingSurface {
                BrowserPeekInitialLoadingSurface()
            }
        }
        .animation(revealAnimation, value: showsInitialLoadingSurface)
        .modifier(
            BrowserPeekPageCardStyleModifier(
                reduceTransparency: reduceTransparency
            )
        )
    }

    private var revealAnimation: Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            BrowserPeekPresentationPolicy.initialContentRevealAnimation,
            reduceMotion: reduceMotion
        )
    }
}

#Preview {
    BrowserPeekPageCard(
        model: BrowserPeekPreviewFixture.makeModel(),
        showsInitialLoadingSurface: false,
        reduceMotion: false,
        reduceTransparency: false
    )
    .frame(width: 640, height: 420)
}
