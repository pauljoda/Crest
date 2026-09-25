@MainActor
final class CloudKitBrowserCloudSyncTransportFactory: BrowserCloudSyncTransportFactory {
    private let configuration: BrowserCloudSyncConfiguration
    private let core: CrestCore
    private let persistence: any BrowserCloudSyncStatePersisting

    init(
        configuration: BrowserCloudSyncConfiguration,
        core: CrestCore,
        persistence: any BrowserCloudSyncStatePersisting
    ) {
        self.configuration = configuration
        self.core = core
        self.persistence = persistence
    }

    func makeTransport(
        statusHandler: @escaping @Sendable (BrowserCloudSyncStatus) async -> Void,
        activityHandler: @escaping @Sendable (BrowserCloudSyncActivity) async -> Void
    ) throws -> any BrowserCloudSyncTransport {
        try BrowserCloudSyncEngine(
            configuration: configuration,
            core: core,
            persistence: persistence,
            statusHandler: statusHandler,
            activityHandler: activityHandler
        )
    }
}
