import SwiftUI

/// What the prompt shows while the Space's vault is answering, and what it shows
/// when the answer is nothing.
struct BrowserCredentialSuggestionState: View {
    let isLoading: Bool
    let suggestions: [CredentialDescriptor]
    let selectedID: UUID?
    let context: BrowserCredentialSuggestionContext
    let metrics: BrowserCredentialPromptMetrics
    let fill: (CredentialDescriptor) -> Void

    @ViewBuilder
    var body: some View {
        if isLoading {
            ProgressView("Checking this Space…")
                .controlSize(.small)
                .frame(minHeight: metrics.suggestionStateMinimumHeight)
        } else if suggestions.isEmpty {
            empty
        } else {
            BrowserCredentialSuggestionList(
                suggestions: suggestions,
                selectedID: selectedID,
                context: context,
                metrics: metrics,
                fill: fill
            )
        }
    }

    /// A panel with nothing to offer says so in a row shaped like the logins
    /// it would list, naming the Space and the site; a band says the whole
    /// sentence, because it has already taken the room to say it in.
    @ViewBuilder
    private var empty: some View {
        switch metrics.suggestionEmptyStatePresentation {
        case .compact:
            HStack(spacing: BrowserCredentialPromptMetrics.suggestionRowSpacing) {
                BrowserCredentialPromptIdentity(
                    kind: .suggestions,
                    iconData: context.iconData,
                    showsSiteIcon: context.iconData != nil,
                    tint: CrestBrandTheme.accent
                )
                VStack(alignment: .leading, spacing: BrowserCredentialPromptMetrics.suggestionRowTextSpacing) {
                    Text("No passwords saved")
                        .font(.callout.weight(.semibold))
                    Text(verbatim: context.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, metrics.suggestionRowHighlightBleed)
            .padding(.vertical, metrics.suggestionRowVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: metrics.suggestionRowMinimumHeight, alignment: .leading)
            .accessibilityElement(children: .combine)
        case .sentence:
            Text("No Crest passwords are saved for this site in this Space.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(
                    minHeight: metrics.suggestionStateMinimumHeight,
                    alignment: .leading
                )
        }
    }
}

#if DEBUG
    #Preview("Loading, empty, and available") {
        let context = BrowserCredentialSuggestionContext(
            iconData: nil, source: "Work · example.test", fillsUsernameOnly: false)
        VStack(spacing: 20) {
            BrowserCredentialSuggestionState(
                isLoading: true, suggestions: [], selectedID: nil, context: context, metrics: .pointer, fill: { _ in })
            BrowserCredentialSuggestionState(
                isLoading: false, suggestions: [], selectedID: nil, context: context, metrics: .pointer, fill: { _ in })
            BrowserCredentialSuggestionState(
                isLoading: false, suggestions: [BrowserCredentialDetailPreviewFixture.descriptor],
                selectedID: BrowserCredentialDetailPreviewFixture.descriptor.id, context: context, metrics: .pointer,
                fill: { _ in })
        }.padding().frame(width: 380)
    }
#endif
