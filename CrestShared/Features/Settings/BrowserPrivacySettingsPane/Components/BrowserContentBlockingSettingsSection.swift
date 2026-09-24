import SwiftUI

struct BrowserContentBlockingSettingsSection: View {
    @Binding var policy: ContentBlockingPolicy
    let errorDescription: String?

    var body: some View {
        Section("Content blocking", systemImage: "hand.raised.slash") {
            Toggle("Block known ads and trackers", isOn: isEnabled)
                .accessibilityIdentifier("content-blocking-enabled")

            Text(
                "Crest uses a small built-in protection set. Install a content-blocking extension for broader coverage or custom lists."
            )
            .crestFormFootnote()

            if policy.blocksContent, let errorDescription {
                Label(
                    errorDescription,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .crestFormFootnote()
                .foregroundStyle(.orange)
            }
        }
    }

    private var isEnabled: Binding<Bool> {
        Binding {
            policy.blocksContent
        } set: { isEnabled in
            policy = .blocking(isEnabled)
        }
    }
}
