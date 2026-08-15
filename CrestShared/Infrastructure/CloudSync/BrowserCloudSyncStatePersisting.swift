protocol BrowserCloudSyncStatePersisting: Sendable {
    func load() throws -> BrowserCloudSyncState?
    func save(_ state: BrowserCloudSyncState) throws
}
