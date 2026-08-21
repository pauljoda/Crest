import SwiftUI

/// What the prompt shows while the Space's vault is answering, and what it shows
/// when the answer is nothing.
struct BrowserCredentialSuggestionState: View {
    let isLoading: Bool
    let suggestions: [CredentialDescriptor]
    let metrics: BrowserCredentialPromptMetrics
    let fill: (CredentialDescriptor) -> Void

    @ViewBuilder
    var body: some View {
        if isLoading {
            ProgressView("Checking this Space…")
                .controlSize(.small)
                .frame(minHeight: metrics.suggestionStateMinimumHeight)
        } else if suggestions.isEmpty {
            Text("No Crest passwords are saved for this site in this Space.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(
                    minHeight: metrics.suggestionStateMinimumHeight,
                    alignment: .leading
                )
        } else {
            BrowserCredentialSuggestionList(
                suggestions: suggestions,
                metrics: metrics,
                fill: fill
            )
        }
    }
}
