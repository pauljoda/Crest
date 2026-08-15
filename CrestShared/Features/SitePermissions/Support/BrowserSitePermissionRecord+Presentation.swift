extension BrowserSitePermissionRecord {
    var displayLabel: String {
        guard let detail, !detail.isEmpty else { return permission.settingsLabel }
        return "\(permission.settingsLabel) (\(detail))"
    }
}
