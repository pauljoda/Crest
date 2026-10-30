import SwiftUI

/// One verification code the prompt can put into the field. The site is named
/// by the prompt's header, so the row says what it is and whose it is.
struct BrowserOneTimeCodeRow: View {
    let code: BrowserOneTimeCodeSuggestion
    let metrics: BrowserCredentialPromptMetrics
    let fill: () -> Void

    var body: some View {
        BrowserCredentialPromptRow(
            symbol: "checkmark.shield.fill",
            title: String(localized: "Verification code"),
            detail: code.username,
            metrics: metrics,
            action: fill
        )
    }
}
