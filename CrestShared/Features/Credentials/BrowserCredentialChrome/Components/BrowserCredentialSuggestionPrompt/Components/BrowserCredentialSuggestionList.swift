import SwiftUI

/// The saved accounts the prompt offers.
///
/// A pointer shell lets the list grow its panel; a touch shell keeps it inside a
/// band it scrolls, because the prompt is pushing the page down while it is up.
struct BrowserCredentialSuggestionList: View {
    let suggestions: [BrowserCredentialSuggestion]
    var codes: [BrowserOneTimeCodeSuggestion] = []
    let offersPairing: Bool
    var offersOpeningPasswordsApp = false
    let metrics: BrowserCredentialPromptMetrics
    let fill: (BrowserCredentialSuggestion) -> Void
    var fillCode: (BrowserOneTimeCodeSuggestion) -> Void = { _ in }
    let beginPairing: () -> Void
    var openPasswordsApp: () -> Void = {}

    @ViewBuilder
    var body: some View {
        if let maximumHeight = metrics.suggestionListMaximumHeight {
            ScrollView {
                LazyVStack(spacing: 0) { rows }
            }
            .frame(maxHeight: maximumHeight)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                rows
            }
            // The rows pad themselves out so their highlight reaches past the
            // text; the list pulls that back so the text still lines up with
            // everything above it.
            .padding(.horizontal, -metrics.suggestionRowHighlightBleed)
        }
    }

    /// Crest's own rows stay as they were until another provider joins them;
    /// from then on each row says whose it is.
    private var showsProvider: Bool {
        suggestions.contains { !$0.provider.keepsSpaceVault }
    }

    @ViewBuilder
    private var rows: some View {
        ForEach(suggestions) { suggestion in
            BrowserCredentialSuggestionRow(
                suggestion: suggestion,
                showsProvider: showsProvider,
                metrics: metrics,
                fill: { fill(suggestion) }
            )
        }
        ForEach(codes) { code in
            BrowserOneTimeCodeRow(code: code, metrics: metrics, fill: { fillCode(code) })
        }
        if offersPairing {
            BrowserCredentialPairingRow(metrics: metrics, begin: beginPairing)
        }
        if offersOpeningPasswordsApp {
            Divider()
            BrowserCredentialOpenPasswordsAppRow(metrics: metrics, open: openPasswordsApp)
        }
    }
}
