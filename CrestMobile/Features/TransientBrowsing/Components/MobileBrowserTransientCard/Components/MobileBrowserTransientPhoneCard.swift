import SwiftUI

struct MobileBrowserTransientPhoneCard: View {
    let model: MobileBrowserTransientOverlayModel
    let state: MobileBrowserTransientPresentationState
    let safeAreaInsets: EdgeInsets
    @Binding var dismissalOffset: CGFloat
    let dismiss: () -> Void
    let promote: (BrowserSpaceRuntimeAssignment) -> Void

    var body: some View {
        VStack(spacing: 8) {
            MobileBrowserTransientPageCard(
                model: model,
                isPhone: true,
                reduceTransparency: state.reduceTransparency
            )
            MobileBrowserTransientActionControls(
                model: model,
                dismiss: dismiss,
                promote: promote
            )
            .frame(maxWidth: BrowserPeekChromePolicy.controlBarWidth)
            .padding(10)
            .opacity(state.controlsOpacity)
            .allowsHitTesting(state.isCardExpanded)
        }
        .padding(cardInsets)
        .offset(
            y: BrowserVisualAccessibilityPolicy.spatialOffset(
                dismissalOffset,
                reduceMotion: state.reduceMotion
            )
        )
        .scaleEffect(state.phoneScale, anchor: .bottom)
        .simultaneousGesture(dismissGesture)
    }

    private var cardInsets: EdgeInsets {
        MobileBrowserTransientLayout.cardInsets(
            safeAreaInsets: safeAreaInsets,
            minimumHorizontal: 14,
            minimumVertical: 10
        )
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard value.translation.height > 0,
                    abs(value.translation.height) > abs(value.translation.width)
                else { return }
                dismissalOffset = value.translation.height
            }
            .onEnded { value in
                guard value.predictedEndTranslation.height <= 120 else {
                    dismiss()
                    return
                }
                withAnimation(
                    BrowserVisualAccessibilityPolicy.animation(
                        CrestMotion.peekDragSettlement,
                        reduceMotion: state.reduceMotion
                    )
                ) {
                    dismissalOffset = 0
                }
            }
    }
}

#Preview {
    @Previewable @State var offset: CGFloat = 0
    MobileBrowserTransientPhoneCard(
        model: MobileBrowserTransientPreviewFixture.makeModel(),
        state: MobileBrowserTransientPreviewFixture.presentationState,
        safeAreaInsets: EdgeInsets(),
        dismissalOffset: $offset,
        dismiss: {},
        promote: { _ in }
    )
}
