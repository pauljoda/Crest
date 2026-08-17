import SwiftUI

struct BrowserPeekSurface: View {
    let model: BrowserPeekModel
    let state: BrowserPeekSurfaceState
    let dismiss: () -> Void
    let promote: (BrowserSpaceRuntimeAssignment) -> Void

    var body: some View {
        GeometryReader { proxy in
            let frame = BrowserPeekPresentationPolicy.desktopWebContentFrame(
                in: proxy.size,
                reservedLeadingWidth: state.reservedLeadingWidth,
                layoutDirection: state.layoutDirection
            )
            let cardSize = BrowserPeekPresentationPolicy.desktopCardSize(
                in: frame.size
            )
            ZStack {
                BrowserPeekScrim(opacity: scrimOpacity, dismiss: dismiss)
                BrowserPeekCardStack(
                    model: model,
                    state: state,
                    cardSize: cardSize,
                    webContentFrame: frame,
                    dismiss: dismiss,
                    promote: promote
                )
            }
        }
        .ignoresSafeArea()
    }

    private var scrimOpacity: Double {
        BrowserVisualAccessibilityPolicy.scrimOpacity(
            state.isCardVisible ? 0.34 : 0,
            reduceTransparency: state.reduceTransparency
        )
    }
}
