import SwiftUI

struct BrowserPeekCardStack: View {
    let model: BrowserPeekModel
    let state: BrowserPeekSurfaceState
    let cardSize: CGSize
    let webContentFrame: CGRect
    let dismiss: () -> Void
    let promote: (BrowserSpaceRuntimeAssignment) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            BrowserPeekActionControls(
                model: model,
                dismiss: dismiss,
                promote: promote
            )
            .opacity(state.isCardExpanded ? 1 : 0)
            .allowsHitTesting(state.isCardExpanded)
            BrowserPeekPageCard(
                model: model,
                showsInitialLoadingSurface:
                    state.showsInitialLoadingSurface(for: model.page),
                reduceMotion: state.reduceMotion,
                reduceTransparency: state.reduceTransparency
            )
            .frame(width: cardSize.width, height: cardSize.height)
            .scaleEffect(
                x: state.cardScaleX,
                y: state.cardScaleY,
                anchor: state.sourceAnchor
            )
            .opacity(state.isCardVisible ? 1 : 0)
        }
        .padding(30)
        .frame(width: webContentFrame.width, height: webContentFrame.height)
        .position(x: webContentFrame.midX, y: webContentFrame.midY)
    }
}

#Preview {
    BrowserPeekCardStack(
        model: BrowserPeekPreviewFixture.makeModel(),
        state: BrowserPeekSurfaceState(
            reservedLeadingWidth: 0,
            layoutDirection: .leftToRight,
            isCardVisible: true,
            isCardExpanded: true,
            isInitialWebContentRevealed: false,
            reduceMotion: false,
            reduceTransparency: false,
            sourcePresentation: .resolved(nil)
        ),
        cardSize: CGSize(width: 640, height: 420),
        webContentFrame: CGRect(x: 0, y: 0, width: 900, height: 620),
        dismiss: {},
        promote: { _ in }
    )
    .frame(width: 900, height: 620)
}
