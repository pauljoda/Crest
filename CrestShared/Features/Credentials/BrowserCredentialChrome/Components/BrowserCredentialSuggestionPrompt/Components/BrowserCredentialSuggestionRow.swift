import SwiftUI

/// One saved account the prompt can put into the form.
///
/// The name the credential was saved under carries the row and the login it
/// signs in with sits under it, because the question a list of accounts answers
/// is *which of mine*. The site is not repeated here: every suggestion is an
/// exact-origin match for the one the header already named.
struct BrowserCredentialSuggestionRow: View {
    let suggestion: BrowserCredentialSuggestion
    /// Whether the row names the provider that issued it.
    var showsProvider = false
    let metrics: BrowserCredentialPromptMetrics
    let fill: () -> Void

    var body: some View {
        BrowserCredentialPromptRow(
            symbol: "person.crop.circle",
            title: title,
            detail: detail,
            metrics: metrics,
            action: fill
        )
    }

    /// What the row is filed under: the name the credential was saved with,
    /// falling back to the login it signs in with.
    private var title: String {
        guard
            let displayName = suggestion.descriptor.displayName?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !displayName.isEmpty
        else {
            return suggestion.descriptor.username
        }
        return displayName
    }

    /// The login under the name, where the name is not already it, and the
    /// provider where more than one is listed.
    private var detail: String? {
        let account = metrics.suggestionRowShowsAccountDetail && title != suggestion.descriptor.username
        let parts = [account ? suggestion.descriptor.username : nil, showsProvider ? suggestion.providerTitle : nil]
        let line = parts.compactMap { $0 }.joined(separator: " · ")
        return line.isEmpty ? nil : line
    }
}

#if DEBUG
    #Preview("Pointer and touch") {
        VStack(spacing: 20) {
            BrowserCredentialSuggestionRow(
                suggestion: BrowserCredentialSuggestion(
                    descriptor: BrowserCredentialDetailPreviewFixture.descriptor, provider: .crestPasswords),
                metrics: .pointer, fill: {})
            BrowserCredentialSuggestionRow(
                suggestion: BrowserCredentialSuggestion(
                    descriptor: BrowserCredentialDetailPreviewFixture.descriptor, provider: .crestPasswords),
                metrics: .touch, fill: {})
        }.padding().frame(width: 380)
    }
#endif
