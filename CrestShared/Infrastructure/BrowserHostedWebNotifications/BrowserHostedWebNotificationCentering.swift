@MainActor
protocol BrowserHostedWebNotificationCentering: AnyObject {
    func currentAuthorization() async -> BrowserHostedWebNotificationAuthorization
    func requestAuthorization() async -> BrowserHostedWebNotificationAuthorization
    func add(
        _ delivery: BrowserHostedWebNotificationDelivery,
        eventHandler: @escaping @MainActor (BrowserHostedWebNotificationEvent) -> Void
    ) async throws
    func remove(identifier: String) async
}
