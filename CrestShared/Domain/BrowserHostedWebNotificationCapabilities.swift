struct BrowserHostedWebNotificationCapabilities: Equatable, Sendable {
    let supportsPermissionDelegation: Bool
    let supportsForegroundPageDelivery: Bool
    let supportsBackgroundPushDelivery: Bool
    let systemOwner: BrowserHostedWebNotificationSystemOwner

    static let wkWebView = BrowserHostedWebNotificationCapabilities(
        supportsPermissionDelegation: true,
        supportsForegroundPageDelivery: true,
        supportsBackgroundPushDelivery: false,
        systemOwner: .crestWhilePageIsLoaded
    )
}
