import SwiftUI

/// The row that starts pairing with Apple Passwords, shaped like the accounts
/// beside it.
struct BrowserCredentialPairingRow: View {
    let metrics: BrowserCredentialPromptMetrics
    let begin: () -> Void

    var body: some View {
        BrowserCredentialPromptRow(
            symbol: "key.viewfinder",
            title: String(localized: "Pair with Apple Passwords"),
            detail: nil,
            metrics: metrics,
            action: begin
        )
    }
}
