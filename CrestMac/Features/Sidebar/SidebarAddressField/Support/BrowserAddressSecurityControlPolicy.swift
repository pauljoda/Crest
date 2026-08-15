enum BrowserAddressSecurityControlPolicy {
    static let controlSize = BrowserTabTrailingControlPolicy.minimumHitTarget

    static func isVisible(
        isAddressEditing: Bool,
        hasActiveSite: Bool
    ) -> Bool {
        !isAddressEditing && hasActiveSite
    }
}
