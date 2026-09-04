import Foundation

/// The watch stream the capability broker subscribes a `runtime.watch` port to.
///
/// Every context of one extension opens its own port, exactly as the
/// `declarativeNetRequest` watch does: the worker owns
/// `runtime.onMessageExternal` in practice, but a side panel or options page
/// may add a listener too, and a single subscriber would leave the others
/// unaware. The first answer to a delivery wins; later ones are dropped.
@MainActor
protocol BrowserExtensionExternalMessageHandling: AnyObject {
    func events(
        for client: BrowserExtensionServiceClientID
    ) -> AsyncStream<BrowserExtensionExternalMessageDelivery>
}
