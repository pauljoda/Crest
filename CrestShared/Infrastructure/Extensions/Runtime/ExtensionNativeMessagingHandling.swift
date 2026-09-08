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
    /// The `content_security_policy` value the package's manifest declared.
    ///
    /// A capability the broker runs outside the WebContent process — a
    /// brokered worker WebSocket is the only one today — is invisible to
    /// WebKit's CSP enforcement, so the broker applies the extension's own
    /// `connect-src` itself. Carrying the raw manifest value keeps the parsing
    /// with the capability that needs it.
    let contentSecurityPolicy: String?

    init(
        grantedPermissions: Set<String> = [],
        clientID: BrowserExtensionServiceClientID? = nil,
        allowsInternalCapabilityBroker: Bool = false,
        contentSecurityPolicy: String? = nil
    ) {
        self.grantedPermissions = grantedPermissions
        self.clientID = clientID
        self.allowsInternalCapabilityBroker = allowsInternalCapabilityBroker
        self.contentSecurityPolicy = contentSecurityPolicy
    }

    func grants(_ permission: String) -> Bool {
        grantedPermissions.contains(permission)
    }
}

@MainActor
protocol BrowserExtensionNativeMessagingHandling: AnyObject {
    /// Whether Crest may launch an **external** native host process on behalf
    /// of an extension. This is the App Sandbox question, and it says nothing
    /// about `BrowserExtensionNativeMessagingApplication
    /// .capabilityBrokerIdentifier`, which is Crest's own in-process
    /// emulation broker: that transport spawns nothing and stays available in
    /// every build, including the sandboxed App Store one.
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
