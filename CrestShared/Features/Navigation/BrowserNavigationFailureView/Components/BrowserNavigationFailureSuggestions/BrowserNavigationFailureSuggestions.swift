import SwiftUI

struct BrowserNavigationFailureSuggestions: View {
    let presentation: BrowserNavigationFailurePresentation
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            Text("Try this")
                .font(.headline)

            BrowserNavigationFailureSuggestionRow(
                suggestion: presentation.primarySuggestion,
                accent: accent
            )
            BrowserNavigationFailureSuggestionRow(
                suggestion: presentation.secondarySuggestion,
                accent: accent
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
    }
}

#Preview("Navigation Failure Suggestions") {
    BrowserNavigationFailureSuggestions(
        presentation: BrowserNavigationFailurePresentation(
            failure: BrowserNavigationFailurePreviewFixture.offline
        ),
        accent: .blue
    )
    .padding()
}
