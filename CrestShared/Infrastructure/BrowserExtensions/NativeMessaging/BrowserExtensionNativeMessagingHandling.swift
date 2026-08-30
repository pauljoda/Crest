import WebKit

enum BrowserExtensionNativeMessagingIdentity: Equatable, Sendable {
    case chromeWebStore(BrowserChromeExtensionID)
    case mozillaAddons(BrowserMozillaExtensionID)
}

enum BrowserExtensionNativeMessagingApplication {
    static let capabilityBrokerIdentifier =
        ProductIdentity.serviceNamespace + ".webextension-compatibility"
}

struct BrowserExtensionNativeMessagingAuthorization: Equatable, Sendable {
    let grantedPermissions: Set<String>
    let clientID: BrowserExtensionServiceClientID?
    let allowsInternalCapabilityBroker: Bool

    init(
        grantedPermissions: Set<String> = [],
        clientID: BrowserExtensionServiceClientID? = nil,
        allowsInternalCapabilityBroker: Bool = false
    ) {
        self.grantedPermissions = grantedPermissions
        self.clientID = clientID
        self.allowsInternalCapabilityBroker = allowsInternalCapabilityBroker
    }

    func grants(_ permission: String) -> Bool {
        grantedPermissions.contains(permission)
    }
}

@MainActor
protocol BrowserExtensionNativeMessagingHandling: AnyObject {
    var capability: BrowserExtensionNativeMessagingCapability { get }

    func sendMessage(
        _ message: Any,
        applicationIdentifier: String?,
        extensionIdentity: BrowserExtensionNativeMessagingIdentity?,
        authorization: BrowserExtensionNativeMessagingAuthorization,
        replyHandler: @escaping (Any?, Error?) -> Void
    )

    func connect(
        port: WKWebExtension.MessagePort,
        extensionIdentity: BrowserExtensionNativeMessagingIdentity?,
        authorization: BrowserExtensionNativeMessagingAuthorization,
        completionHandler: @escaping (Error?) -> Void
    )
}
