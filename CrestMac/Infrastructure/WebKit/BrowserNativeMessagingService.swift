import Foundation
import WebKit

@MainActor
final class BrowserNativeMessagingService:
    BrowserExtensionNativeMessagingHandling
{
    let capability: BrowserExtensionNativeMessagingCapability
    private let resolver: BrowserNativeMessagingHostManifestResolver
    private let replyTimeout: Duration
    private var connections: [ObjectIdentifier: BrowserNativeMessagingPersistentConnection] = [:]

    init(
        capability: BrowserExtensionNativeMessagingCapability,
        resolver: BrowserNativeMessagingHostManifestResolver,
        replyTimeout: Duration = .seconds(30)
    ) {
        self.capability = capability
        self.resolver = resolver
        self.replyTimeout = replyTimeout
    }

    static func production() -> BrowserNativeMessagingService {
        BrowserNativeMessagingService(
            capability:
                BrowserPlatformExtensionNativeMessagingCapability.currentBuild,
            resolver: .production()
        )
    }

    func sendMessage(
        _ message: Any,
        applicationIdentifier: String?,
        extensionIdentity: BrowserExtensionNativeMessagingIdentity,
        replyHandler: @escaping (Any?, Error?) -> Void
    ) {
        guard capability == .available else {
            replyHandler(nil, BrowserExtensionNativeMessagingError.unavailable)
            return
        }
        do {
            let host = try resolver.resolve(
                hostName: applicationIdentifier ?? "",
                extensionIdentity: extensionIdentity
            )
            var connection: BrowserNativeMessagingProcessConnection?
            // One reply completes this exchange, so bound the wait: a host that
            // never answers would otherwise hold its child process and pipes
            // for as long as the browser runs.
            connection = try BrowserNativeMessagingProcessConnection(
                host: host,
                replyTimeout: replyTimeout,
                receive: { value in
                    guard connection != nil else { return }
                    replyHandler(value, nil)
                    let completedConnection = connection
                    connection = nil
                    completedConnection?.disconnect()
                },
                disconnect: { error in
                    guard connection != nil else { return }
                    replyHandler(nil, error)
                    connection = nil
                }
            )
            try connection?.send(message)
        } catch {
            replyHandler(nil, error)
        }
    }

    func connect(
        port: WKWebExtension.MessagePort,
        extensionIdentity: BrowserExtensionNativeMessagingIdentity,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard capability == .available else {
            completionHandler(
                BrowserExtensionNativeMessagingError.unavailable
            )
            return
        }
        do {
            let host = try resolver.resolve(
                hostName: port.applicationIdentifier ?? "",
                extensionIdentity: extensionIdentity
            )
            let key = ObjectIdentifier(port)
            // A persistent port may idle for as long as the extension keeps it
            // open, and its disconnect handler already bounds the child, so
            // this direction stays untimed.
            let connection = try BrowserNativeMessagingProcessConnection(
                host: host,
                receive: { [weak self] message in
                    self?.connections[key]?.port.sendMessage(
                        message,
                        completionHandler: nil
                    )
                },
                disconnect: { [weak self] error in
                    if let persistentConnection = self?.connections
                        .removeValue(forKey: key),
                        !persistentConnection.port.isDisconnected
                    {
                        persistentConnection.port.disconnect()
                    }
                    _ = error
                }
            )
            connections[key] = BrowserNativeMessagingPersistentConnection(
                port: port,
                process: connection
            )
            port.messageHandler = { [weak self] message, error in
                guard let connection = self?.connections[key]?.process else {
                    return
                }
                if let error {
                    connection.disconnect(error: error)
                    return
                }
                do {
                    try connection.send(message ?? NSNull())
                } catch {
                    connection.disconnect(error: error)
                }
            }
            port.disconnectHandler = { [weak self] _ in
                self?.connections.removeValue(forKey: key)?.process.disconnect()
            }
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    func sendMessage(
        _ message: Any,
        applicationIdentifier: String?,
        extensionID: BrowserChromeExtensionID,
        replyHandler: @escaping (Any?, Error?) -> Void
    ) {
        sendMessage(
            message,
            applicationIdentifier: applicationIdentifier,
            extensionIdentity: .chromeWebStore(extensionID),
            replyHandler: replyHandler
        )
    }
}
