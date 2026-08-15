protocol BrowserCloudSyncTransport: Sendable {
    func start() async
    func syncNow() async throws
    func notifyLocalChanges() async
}
