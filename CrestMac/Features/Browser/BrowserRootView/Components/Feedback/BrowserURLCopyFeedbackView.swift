import SwiftUI

struct BrowserURLCopyFeedbackView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Label("URL Copied", systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.semibold))
            .padding(
                .horizontal,
                BrowserRootMetrics.urlCopyFeedbackHorizontalPadding
            )
            .frame(height: BrowserRootMetrics.urlCopyFeedbackHeight)
            .glassEffect(.regular, in: .capsule)
            .shadow(
                color: .black.opacity(
                    reduceTransparency ? 0 : CrestOpacity.controlShadow
                ),
                radius: BrowserRootMetrics.urlCopyFeedbackShadowRadius,
                y: BrowserRootMetrics.urlCopyFeedbackShadowYOffset
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .top
            )
            .padding(.top, BrowserRootMetrics.urlCopyFeedbackTopInset)
            .allowsHitTesting(false)
            .accessibilityAddTraits(.isStaticText)
            .transition(
                reduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity)
            )
            .zIndex(BrowserRootMetrics.feedbackZIndex)
    }
}
