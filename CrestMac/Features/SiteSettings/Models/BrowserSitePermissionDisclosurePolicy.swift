enum BrowserSitePermissionDisclosurePolicy {
    static let defaultIsExpanded = true

    static func visiblePermissions(
        isExpanded: Bool
    ) -> [SitePermission] {
        isExpanded ? SitePermission.all : []
    }
}
