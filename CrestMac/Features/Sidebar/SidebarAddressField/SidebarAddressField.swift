import SwiftUI

struct SidebarAddressField: View {
    @Binding var text: String
    @Binding var isEditing: Bool
    let focusRequest: Int
    let isSecure: Bool
    let progress: Double
    let isLoading: Bool
    var hasResidentPage = true
    let activate: (() -> Void)?
    let submit: () -> Void
    let morphNamespace: Namespace.ID
    let morphID: String
    var siteControl: BrowserSiteControlConfiguration? = nil
    var addressAccessibilityLabel: LocalizedStringKey = "Address and search"
    var addressAccessibilityIdentifier = "address-field"
    var addressDisplayAccessibilityIdentifier = "address-display"
    var prompt: LocalizedStringKey = "Search or enter website"

    var body: some View {
        SidebarAddressFieldContent(configuration: contentConfiguration)
            .browserAddressFieldSurface(
                progress: progress,
                isLoading: isLoading,
                isEditing: isEditing
            )
            .matchedGeometryEffect(
                id: morphID,
                in: morphNamespace,
                properties: .frame,
                anchor: .center,
                isSource: true
            )
    }

    private var contentConfiguration: SidebarAddressFieldConfiguration {
        SidebarAddressFieldConfiguration(
            text: $text,
            isEditing: $isEditing,
            focusRequest: focusRequest,
            isSecure: isSecure,
            hasResidentPage: hasResidentPage,
            activate: activate,
            submit: submit,
            siteControl: siteControl,
            addressAccessibilityLabel: addressAccessibilityLabel,
            addressAccessibilityIdentifier: addressAccessibilityIdentifier,
            addressDisplayAccessibilityIdentifier: addressDisplayAccessibilityIdentifier,
            prompt: prompt
        )
    }
}
