import WebKit

@MainActor
protocol BrowserExtensionNativeMessagingHandling: AnyObject {
    var capability: BrowserExtensionNativeMessagingCapability { get }

    func sendMessage(
        _ message: Any,
        applicationIdentifier: String?,
        extensionID: BrowserChromeExtensionID,
        replyHandler: @escaping (Any?, Error?) -> Void
    )

    func connect(
        port: WKWebExtension.MessagePort,
        extensionID: BrowserChromeExtensionID,
        completionHandler: @escaping (Error?) -> Void
    )
}
