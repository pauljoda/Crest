import SwiftUI
import UIKit

struct MobileBrowserTransientSurface: View {
    let model: MobileBrowserTransientOverlayModel
    let state: MobileBrowserTransientPresentationState
    @Binding var dismissalOffset: CGFloat
    let dismiss: () -> Void
    let promote: (BrowserSpaceRuntimeAssignment) -> Void

    var body: some View {
        GeometryReader { proxy in
            MobileBrowserTransientCard(
                model: model,
                state: state,
                availableSize: proxy.size,
                safeAreaInsets: proxy.safeAreaInsets,
                isPhone: isPhone,
                dismissalOffset: $dismissalOffset,
                dismiss: dismiss,
                promote: promote
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(
                x: state.cardScaleX,
                y: state.cardScaleY,
                anchor: state.sourceTransform.anchor
            )
            .opacity(state.cardOpacity)
        }
        .background {
            MobileBrowserTransientScrim(
                opacity: state.scrimOpacity,
                allowsDismissal: !isPhone,
                dismiss: dismiss
            )
        }
    }

    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
}

#Preview {
    @Previewable @State var offset: CGFloat = 0
    MobileBrowserTransientSurface(
        model: MobileBrowserTransientPreviewFixture.makeModel(),
        state: MobileBrowserTransientPreviewFixture.presentationState,
        dismissalOffset: $offset,
        dismiss: {},
        promote: { _ in }
    )
}
