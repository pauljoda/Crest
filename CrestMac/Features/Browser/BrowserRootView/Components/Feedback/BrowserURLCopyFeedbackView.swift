import SwiftUI

struct BrowserURLCopyFeedbackView: View {
    let title: LocalizedStringKey
    let systemImage: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        _ title: LocalizedStringKey = "URL Copied",
        systemImage: String = "checkmark.circle.fill"
    ) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
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

#if DEBUG
    #Preview("Component") {
        BrowserURLCopyFeedbackView().padding().frame(width: 320, height: 150)
    }
#endif
