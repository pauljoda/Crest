import SwiftUI

struct SidebarAddressFieldContent: View {
    let configuration: SidebarAddressFieldConfiguration

    var body: some View {
        HStack(spacing: 7) {
            BrowserAddressLeadingControl(configuration: configuration)
            BrowserAddressEditor(configuration: configuration)

            if BrowserSiteControlPresentationPolicy.isVisible(
                isAddressEditing: configuration.isEditing.wrappedValue,
                hasActiveSite: configuration.siteControl != nil
            ), let siteControl = configuration.siteControl {
                BrowserSiteControlButton(configuration: siteControl)
            }
        }
    }
}

#Preview {
    @Previewable @State var text = "https://example.com"
    @Previewable @State var isEditing = false

    SidebarAddressFieldContent(
        configuration: SidebarAddressFieldPreviewFixture.configuration(
            text: $text,
            isEditing: $isEditing
        )
    )
    .frame(width: 420)
    .padding()
}
