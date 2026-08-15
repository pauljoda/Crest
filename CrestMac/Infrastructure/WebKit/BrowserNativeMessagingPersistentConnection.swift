import WebKit

struct BrowserNativeMessagingPersistentConnection {
    let port: WKWebExtension.MessagePort
    let process: BrowserNativeMessagingProcessConnection
}
