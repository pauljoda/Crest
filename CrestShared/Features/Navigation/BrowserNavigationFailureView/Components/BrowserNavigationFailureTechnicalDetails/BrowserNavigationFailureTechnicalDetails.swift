import SwiftUI

struct BrowserNavigationFailureTechnicalDetails: View {
    let failure: BrowserNavigationFailure

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            Text("Technical Details")
                .font(.headline)

            if let failingURL = failure.failingURL {
                BrowserNavigationFailureDetailRow(
                    label: "Address",
                    value: failingURL.absoluteString
                )
            }
            BrowserNavigationFailureDetailRow(
                label: "Error Domain",
                value: failure.errorDomain
            )
            BrowserNavigationFailureDetailRow(
                label: "Error Number",
                value: String(failure.errorCode)
            )
            BrowserNavigationFailureDetailRow(
                label: "Loading Stage",
                value: failure.phase == .provisional
                    ? String(localized: "Before content loaded")
                    : String(localized: "After content started loading")
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrowserNavigationFailureMetrics.surfacePadding)
        .background(
            .primary.opacity(BrowserNavigationFailureMetrics.surfaceOpacity),
            in: .rect(
                cornerRadius: BrowserNavigationFailureMetrics.surfaceCornerRadius
            )
        )
        .textSelection(.enabled)
    }
}
