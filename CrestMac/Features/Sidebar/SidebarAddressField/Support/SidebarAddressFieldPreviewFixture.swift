import SwiftUI

@MainActor
enum SidebarAddressFieldPreviewFixture {
    static func configuration(
        text: Binding<String>,
        isEditing: Binding<Bool>
    ) -> SidebarAddressFieldConfiguration {
        SidebarAddressFieldConfiguration(
            text: text,
            isEditing: isEditing,
            focusRequest: 0,
            isSecure: true,
            hasResidentPage: true,
            activate: {},
            submit: {},
            siteControl: makeSiteControl(),
            addressAccessibilityLabel: "Address and search",
            addressAccessibilityIdentifier: "preview-address-field",
            addressDisplayAccessibilityIdentifier: "preview-address-display",
            prompt: "Search or enter website"
        )
    }

    static func makeSiteControl() -> BrowserSiteControlConfiguration {
        BrowserSidebarExtensionPreviewFixture.makeContext().configuration
    }
}
