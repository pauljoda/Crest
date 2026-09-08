extension BrowserSitePermissionCenter {
    convenience init() {
        self.init(persistence: InMemoryBrowserSitePermissionPersistence())
    }

    static func production(reset: Bool = false) -> BrowserSitePermissionCenter {
        let persistence = UserDefaultsBrowserSitePermissionPersistence()
        if reset {
            persistence.save([])
        }
        return BrowserSitePermissionCenter(persistence: persistence)
    }
}
