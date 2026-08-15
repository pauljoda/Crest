@MainActor
final class CloudKitBrowserCloudSyncTransportFactory: BrowserCloudSyncTransportFactory {
    private let configuration: BrowserCloudSyncConfiguration
    private let gateway: any BrowserCloudSyncModelGateway
    private let persistence: any BrowserCloudSyncStatePersisting

    init(
        configuration: BrowserCloudSyncConfiguration,
        gateway: any BrowserCloudSyncModelGateway,
        persistence: any BrowserCloudSyncStatePersisting
    ) {
        self.configuration = configuration
        self.gateway = gateway
        self.persistence = persistence
    }

    func makeTransport(
        statusHandler: @escaping @Sendable (BrowserCloudSyncStatus) async -> Void,
        activityHandler: @escaping @Sendable (BrowserCloudSyncActivity) async -> Void
    ) throws -> any BrowserCloudSyncTransport {
        try BrowserCloudSyncEngine(
            configuration: configuration,
            gateway: gateway,
            persistence: persistence,
            statusHandler: statusHandler,
            activityHandler: activityHandler
        )
    }
}
