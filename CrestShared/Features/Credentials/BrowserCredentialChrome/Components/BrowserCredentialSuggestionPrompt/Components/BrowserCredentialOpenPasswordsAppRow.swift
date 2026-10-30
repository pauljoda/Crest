import SwiftUI

/// The last row of the list: opens Apple's Passwords app on the site. It is
/// shorter than an account row because it says only what it does.
struct BrowserCredentialOpenPasswordsAppRow: View {
    let metrics: BrowserCredentialPromptMetrics
    let open: () -> Void

    var body: some View {
        BrowserCredentialPromptRow(
            symbol: "arrow.up.forward.square",
            title: String(localized: "Open Passwords App"),
            detail: nil,
            trailingSymbol: nil,
            metrics: metrics,
            action: open
        )
    }
}
