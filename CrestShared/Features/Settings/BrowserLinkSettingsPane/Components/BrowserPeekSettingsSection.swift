import SwiftUI

struct BrowserPeekSettingsSection: View {
    @Binding var automaticallyOpensPeek: Bool
    @Binding var clickModifier: LinkPeekModifier
    /// Absent where links can't be dragged out of a page.
    var dragsLinksToPeek: Binding<Bool>? = nil
    /// Absent where the page behind Peek is not dimmed.
    var dimsPageBehindPeek: Binding<Bool>? = nil
    /// Absent where Peek fills the screen.
    var peekSize: CrestSettingValue<Double>? = nil
    /// Opens a sample Peek over Settings; absent where Settings can't show one.
    var testPeek: (() -> Void)? = nil

    var body: some View {
        Section {
            Toggle(
                "Open cross-site links from pinned and saved tabs in Peek",
                isOn: $automaticallyOpensPeek
            )
            .accessibilityIdentifier("automatic-peek")

            Picker("Open Peek with", selection: $clickModifier) {
                ForEach(LinkPeekModifier.all, id: \.self) { modifier in
                    Text(modifier.title).tag(modifier)
                }
            }
            .accessibilityIdentifier("peek-click-modifier")

            if let dragsLinksToPeek {
                Toggle("Drag links to Peek", isOn: dragsLinksToPeek)
                    .accessibilityIdentifier("drag-links-to-peek-toggle")
            }

            if let dimsPageBehindPeek {
                Toggle("Dim the page behind Peek", isOn: dimsPageBehindPeek)
                    .accessibilityIdentifier("dim-page-behind-peek-toggle")
            }

            if let peekSize {
                CrestSettingSlider(
                    "Peek size",
                    value: peekSize,
                    range: BrowserTransientCardArrangement.pointerCardShares,
                    identifier: "peek-size"
                )
            }

            if let testPeek {
                Button("Test Peek", systemImage: "rectangle.on.rectangle", action: testPeek)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("test-peek")
            }
        } header: {
            Text("Peek")
        } footer: {
            CrestFormFootnote(
                dragsLinksToPeek == nil
                    ? "Command-click opens a new tab, or Option-click when Command opens Peek."
                    : "Command-click opens a new tab, or Option-click when Command opens Peek. Hold Option to drag the link itself."
            )
        }
    }
}
