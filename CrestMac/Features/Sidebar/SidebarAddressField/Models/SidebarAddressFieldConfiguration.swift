import SwiftUI

struct SidebarAddressFieldConfiguration {
    let text: Binding<String>
    let isEditing: Binding<Bool>
    let focusRequest: Int
    let isSecure: Bool
    let hasResidentPage: Bool
    let activate: (() -> Void)?
    let submit: () -> Void
    let siteControl: BrowserSiteControlConfiguration?
    let addressAccessibilityLabel: LocalizedStringKey
    let addressAccessibilityIdentifier: String
    let addressDisplayAccessibilityIdentifier: String
    let prompt: LocalizedStringKey
}
