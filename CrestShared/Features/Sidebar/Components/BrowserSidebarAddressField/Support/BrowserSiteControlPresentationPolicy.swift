enum BrowserSiteControlPresentationPolicy {
    static func isVisible(
        isAddressEditing: Bool,
        hasActiveSite: Bool
    ) -> Bool {
        !isAddressEditing && hasActiveSite
    }
}
