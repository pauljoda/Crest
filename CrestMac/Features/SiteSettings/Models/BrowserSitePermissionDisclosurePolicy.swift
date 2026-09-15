enum BrowserSitePermissionDisclosurePolicy {
    static let defaultIsExpanded = true

    static func visiblePermissions(
        isExpanded: Bool
    ) -> [BrowserSitePermission] {
        isExpanded ? BrowserSitePermission.allCases : []
    }
}
