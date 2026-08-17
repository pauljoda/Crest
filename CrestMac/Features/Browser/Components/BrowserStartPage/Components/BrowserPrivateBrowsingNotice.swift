import SwiftUI

struct BrowserPrivateBrowsingNotice: View {
    var body: some View {
        VStack(spacing: 6) {
            Label(
                "Private Browsing",
                systemImage: BrowserPrivateBrowsingAppearance.symbol
            )
            .font(.headline)
            Text(
                "Crest does not save this session or use Crest Passwords. Website data stays in memory only."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("private-browsing-notice")
    }
}
