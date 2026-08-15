struct BrowserHostedWebNotificationCapabilities: Equatable, Sendable {

    let supportsPermissionDelegation: Bool
    let supportsBackgroundPushDelivery: Bool
    let systemOwner: BrowserHostedWebNotificationSystemOwner

    static let wkWebView = BrowserHostedWebNotificationCapabilities(
        supportsPermissionDelegation: false,
        supportsBackgroundPushDelivery: false,
        systemOwner: .safariOrInstalledWebApp
    )
}
