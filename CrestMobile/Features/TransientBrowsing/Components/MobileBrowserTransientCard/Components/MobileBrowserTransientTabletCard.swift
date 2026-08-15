import SwiftUI

struct MobileBrowserTransientTabletCard: View {
    let model: MobileBrowserTransientOverlayModel
    let state: MobileBrowserTransientPresentationState
    let availableSize: CGSize
    let safeAreaInsets: EdgeInsets
    let dismiss: () -> Void
    let promote: (BrowserSpaceRuntimeAssignment) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            MobileBrowserTransientPageCard(
                model: model,
                isPhone: false,
                reduceTransparency: state.reduceTransparency
            )
            .frame(
                width: min(max(availableSize.width * 0.76, 600), 1_180),
                height: min(max(availableSize.height * 0.78, 430), 820)
            )
            MobileBrowserTransientActionControls(
                model: model,
                dismiss: dismiss,
                promote: promote
            )
            .frame(width: BrowserPeekChromePolicy.controlBarWidth)
            .opacity(state.controlsOpacity)
            .allowsHitTesting(state.isCardExpanded)
        }
        .padding(cardInsets)
    }

    private var cardInsets: EdgeInsets {
        MobileBrowserTransientLayout.cardInsets(
            safeAreaInsets: safeAreaInsets,
            minimumHorizontal: 28,
            minimumVertical: 28
        )
    }
}

#Preview {
    MobileBrowserTransientTabletCard(
        model: MobileBrowserTransientPreviewFixture.makeModel(),
        state: MobileBrowserTransientPreviewFixture.presentationState,
        availableSize: CGSize(width: 1_024, height: 768),
        safeAreaInsets: EdgeInsets(),
        dismiss: {},
        promote: { _ in }
    )
    .frame(width: 1_024, height: 768)
}
