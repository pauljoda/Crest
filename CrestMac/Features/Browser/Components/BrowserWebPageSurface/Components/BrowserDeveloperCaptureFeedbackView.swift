import SwiftUI

struct BrowserDeveloperCaptureFeedbackView: View {
    let feedback: String

    var body: some View {
        Label(feedback, systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.semibold))
            .padding(
                .horizontal,
                BrowserWebPageSurfaceMetrics.feedbackHorizontalPadding
            )
            .frame(height: BrowserWebPageSurfaceMetrics.feedbackHeight)
            .background(.regularMaterial, in: .capsule)
            .shadow(
                color: .black.opacity(
                    BrowserWebPageSurfaceMetrics.feedbackShadowOpacity
                ),
                radius: BrowserWebPageSurfaceMetrics.feedbackShadowRadius,
                y: BrowserWebPageSurfaceMetrics.feedbackShadowY
            )
            .padding(.top, BrowserWebPageSurfaceMetrics.feedbackTopPadding)
            .allowsHitTesting(false)
            .accessibilityAddTraits(.isStaticText)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

#Preview("Developer Capture Feedback", traits: .sizeThatFitsLayout) {
    BrowserDeveloperCaptureFeedbackView(feedback: "Capture Copied")
        .padding()
}
