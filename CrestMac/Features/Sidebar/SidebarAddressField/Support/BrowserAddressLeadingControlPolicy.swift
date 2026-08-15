enum BrowserAddressLeadingControlPolicy {
    static func showsPlaceholderGlyph(
        isAddressEditing: Bool,
        hasActiveSite: Bool,
        hasAddress: Bool,
        hasResidentPage: Bool
    ) -> Bool {
        guard !BrowserAddressSecurityControlPolicy.isVisible(
            isAddressEditing: isAddressEditing,
            hasActiveSite: hasActiveSite
        ) else {
            return false
        }
        if isAddressEditing { return true }
        return !hasAddress || hasResidentPage
    }
}
