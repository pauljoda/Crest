import SwiftUI

struct MobileURLCopyFeedback: View {
    let isVisible: Bool
    let topPadding: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    var body: some View {
        if isVisible {
            Label("URL Copied", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
                .padding(
                    .horizontal,
                    MobileBrowserRootLayout.feedbackHorizontalPadding
                )
                .frame(height: MobileBrowserRootLayout.feedbackHeight)
                .glassEffect(.regular, in: .capsule)
                .shadow(
                    color: .black.opacity(
                        reduceTransparency ? 0 : CrestOpacity.controlShadow
                    ),
                    radius: MobileBrowserRootLayout.feedbackShadowRadius,
                    y: MobileBrowserRootLayout.feedbackShadowOffset
                )
                .padding(.top, topPadding)
                .allowsHitTesting(false)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .top).combined(with: .opacity)
                )
                .zIndex(MobileBrowserRootLayout.feedbackLayer)
        }
    }
}

#Preview("Mobile Browser — URL Copy Feedback", traits: .fixedLayout(width: 390, height: 100)) {
    MobileURLCopyFeedback(
        isVisible: true,
        topPadding: MobileBrowserRootLayout.compactOverlayTopPadding
    )
}
