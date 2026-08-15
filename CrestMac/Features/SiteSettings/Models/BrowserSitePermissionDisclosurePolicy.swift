enum BrowserSitePermissionDisclosurePolicy {
    static let defaultIsExpanded = false

    static func visiblePermissions(
        isExpanded: Bool
    ) -> [BrowserSitePermission] {
        isExpanded ? BrowserSitePermission.allCases : []
    }
}
