import SwiftUI

struct BrowserAddressLeadingControl: View {
    let configuration: SidebarAddressFieldConfiguration

    @ViewBuilder
    var body: some View {
        if BrowserAddressSecurityControlPolicy.isVisible(
            isAddressEditing: configuration.isEditing.wrappedValue,
            hasActiveSite: configuration.siteControl != nil
        ), let siteControl = configuration.siteControl {
            BrowserAddressSecurityButton(
                page: siteControl.page,
                isSecure: configuration.isSecure
            )
        } else if BrowserAddressLeadingControlPolicy.showsPlaceholderGlyph(
            isAddressEditing: configuration.isEditing.wrappedValue,
            hasActiveSite: configuration.siteControl != nil,
            hasAddress: !configuration.text.wrappedValue.isEmpty,
            hasResidentPage: configuration.hasResidentPage
        ) {
            BrowserAddressPlaceholderGlyph(isSecure: configuration.isSecure)
        }
    }
}

#Preview {
    @Previewable @State var text = "https://example.com"
    @Previewable @State var isEditing = false

    BrowserAddressLeadingControl(
        configuration: SidebarAddressFieldPreviewFixture.configuration(
            text: $text,
            isEditing: $isEditing
        )
    )
    .padding()
}
