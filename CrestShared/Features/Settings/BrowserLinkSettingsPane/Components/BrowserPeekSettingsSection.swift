import SwiftUI

struct BrowserPeekSettingsSection: View {
    @Binding var automaticallyOpensPeek: Bool
    @Binding var clickModifier: BrowserLinkClickModifier

    var body: some View {
        Section("Peek") {
            Toggle(
                "Open cross-site links from pinned and saved tabs in Peek",
                isOn: $automaticallyOpensPeek
            )
            .accessibilityIdentifier("automatic-peek")

            Picker("Open Peek with", selection: $clickModifier) {
                ForEach(BrowserLinkClickModifier.allCases, id: \.self) { modifier in
                    Text(modifier.title).tag(modifier)
                }
            }
            .accessibilityIdentifier("peek-click-modifier")

            Text("The other modifier opens the link in a new tab.")
                .crestFormFootnote()

            BrowserPlatformLinkSettingsGuidance(
                kind: .peek,
                peekClickModifier: clickModifier
            )
        }
    }
}

#Preview("Peek Settings") {
    @Previewable @State var automaticallyOpensPeek = true
    @Previewable @State var clickModifier = BrowserLinkClickModifier.command
    Form {
        BrowserPeekSettingsSection(
            automaticallyOpensPeek: $automaticallyOpensPeek,
            clickModifier: $clickModifier
        )
    }
    .formStyle(.grouped)
}
