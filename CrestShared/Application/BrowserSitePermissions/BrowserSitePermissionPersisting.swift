protocol BrowserSitePermissionPersisting: AnyObject {
    func load() -> [BrowserSitePermissionRecord]
    func save(_ records: [BrowserSitePermissionRecord])
}
