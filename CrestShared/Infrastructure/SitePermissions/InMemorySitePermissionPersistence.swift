final class InMemoryBrowserSitePermissionPersistence: BrowserSitePermissionPersisting {
    private(set) var records: [BrowserSitePermissionRecord]

    init(records: [BrowserSitePermissionRecord] = []) {
        self.records = records
    }

    func load() -> [BrowserSitePermissionRecord] {
        records
    }

    func save(_ records: [BrowserSitePermissionRecord]) {
        self.records = records
    }
}
