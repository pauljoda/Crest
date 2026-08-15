import SwiftUI

struct BrowserContentBlockingSettingsSection: View {
    @Binding var policy: BrowserContentBlockingPolicy
    let errorDescription: String?

    var body: some View {
        Section("Content blocking") {
            Toggle("Block known ads and trackers", isOn: isEnabled)
                .accessibilityIdentifier("content-blocking-enabled")

            Text(
                "Crest uses a small built-in protection set. Install a content-blocking extension for broader coverage or custom lists."
            )
            .crestFormFootnote()

            if policy == .balanced, let errorDescription {
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
            policy == .balanced
        } set: { isEnabled in
            policy = isEnabled ? .balanced : .off
        }
    }
}

#Preview("Content Blocking") {
    @Previewable @State var policy = BrowserContentBlockingPolicy.balanced
    Form {
        BrowserContentBlockingSettingsSection(
            policy: $policy,
            errorDescription: nil
        )
    }
}
