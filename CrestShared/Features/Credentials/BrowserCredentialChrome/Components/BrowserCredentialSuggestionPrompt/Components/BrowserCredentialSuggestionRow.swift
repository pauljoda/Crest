import SwiftUI

struct BrowserCredentialSuggestionRow: View {
    let suggestion: CredentialDescriptor
    let metrics: BrowserCredentialPromptMetrics
    let fill: () -> Void

    var body: some View {
        Button(action: fill) {
            HStack(spacing: BrowserCredentialPromptMetrics.suggestionRowSpacing) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)
                Text(suggestion.username)
                    .lineLimit(1)
                Spacer(
                    minLength: BrowserCredentialPromptMetrics
                        .suggestionRowSpacerLength
                )
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.tint)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: metrics.suggestionRowMinimumHeight,
                alignment: .leading
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, metrics.suggestionRowVerticalPadding)
    }
}
