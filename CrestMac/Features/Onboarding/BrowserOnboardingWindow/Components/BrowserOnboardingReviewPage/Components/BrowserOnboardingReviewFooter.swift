import SwiftUI

struct BrowserOnboardingReviewFooter: View {
    let failure: BrowserOnboardingFailureText?
    let summary: LocalizedStringResource?
    let isCommitting: Bool
    let isFinalSpace: Bool
    let isImportDisabled: Bool
    let actionTitle: LocalizedStringResource
    let back: () -> Void
    let advance: () -> Void

    var body: some View {
        HStack {
            Button("Back", action: back)
                .buttonStyle(BrowserOnboardingSecondaryButtonStyle())
                .disabled(isCommitting)
                .accessibilityIdentifier("onboarding-back")
            Spacer()
            if let failure {
                Label {
                    BrowserOnboardingFailureMessage(message: failure)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(BrowserOnboardingTypography.sans(11, weight: .medium))
                .foregroundStyle(.red)
                .lineLimit(2)
                .accessibilityIdentifier("onboarding-workflow-error")
            } else if let summary {
                Text(summary)
                    .font(
                        BrowserOnboardingTypography.sans(
                            12,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(BrowserOnboardingPalette.inkSoft)
            }
            Button(action: advance) {
                Text(actionTitle)
            }
            .buttonStyle(BrowserOnboardingPrimaryButtonStyle())
            .controlSize(.large)
            .disabled(isCommitting || (isFinalSpace && isImportDisabled))
            .accessibilityIdentifier(
                isFinalSpace
                    ? "onboarding-confirm-import"
                    : "onboarding-review-next-space"
            )
        }
        .padding(18)
        .background(BrowserOnboardingPalette.paper)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(BrowserOnboardingPalette.line)
                .frame(height: 1)
        }
    }
}

#Preview("Review Footer") {
    BrowserOnboardingReviewFooter(
        failure: nil,
        summary: "1 Space and 1 tab selected",
        isCommitting: false,
        isFinalSpace: true,
        isImportDisabled: false,
        actionTitle: "Import Reviewed Data",
        back: {},
        advance: {}
    )
    .frame(width: 980)
}
