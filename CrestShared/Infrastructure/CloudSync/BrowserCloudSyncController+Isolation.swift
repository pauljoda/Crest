extension BrowserCloudSyncController {
    static func isolated(browser: BrowserStore) -> BrowserCloudSyncController {
        BrowserCloudSyncController(
            workflow: browser,
            configuration: nil,
            preferences: InMemoryBrowserCloudSyncPreferences(),
            remoteService: nil,
            transportFactory: nil
        )
    }
}
