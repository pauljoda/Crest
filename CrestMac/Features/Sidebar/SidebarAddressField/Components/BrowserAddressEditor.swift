import SwiftUI

struct BrowserAddressEditor: View {
    let configuration: SidebarAddressFieldConfiguration

    var body: some View {
        Group {
            BrowserAddressContent(
                text: configuration.text,
                isEditing: configuration.isEditing,
                focusRequest: configuration.focusRequest,
                activate: configuration.activate,
                editorAccessibilityLabel: configuration.addressAccessibilityLabel,
                editorAccessibilityIdentifier: configuration.addressAccessibilityIdentifier,
                summaryAccessibilityIdentifier: configuration.addressDisplayAccessibilityIdentifier,
                prompt: configuration.prompt,
                submit: configuration.submit
            )

            if configuration.isEditing.wrappedValue,
                !configuration.text.wrappedValue.isEmpty
            {
                BrowserAddressClearButton(text: configuration.text)
            }
        }
    }
}

#Preview {
    @Previewable @State var text = "https://example.com"
    @Previewable @State var isEditing = true

    BrowserAddressEditor(
        configuration: SidebarAddressFieldPreviewFixture.configuration(
            text: $text,
            isEditing: $isEditing
        )
    )
    .frame(width: 360)
    .padding()
}
