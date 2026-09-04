import Foundation

/// One web page's `runtime.sendMessage(extensionID, …)` on its way to an
/// extension's `runtime.onMessageExternal`, relayed by Crest.
///
/// WebKit routes that call itself for an ordinary browser tab. It cannot route
/// one from a frame inside a Crest-hosted extension document — its
/// `runtimeWebPageSendMessage` requires the sending page to resolve to a
/// browser tab, and a side panel is deliberately never a tab (nor is it one in
/// Chrome, where `sender.tab` is simply undefined there). Crest carries those
/// deliveries instead.
///
/// The message and the answer travel as JSON, not as a live object graph. That
/// keeps the value `Sendable` for the watch stream, and it means only
/// JSON-representable content ever reaches an extension — a page cannot hand
/// one a host object through this path.
struct BrowserExtensionExternalMessageDelivery: Equatable, Sendable {
    /// Matches this delivery to the extension's one-shot reply.
    let requestID: String
    /// The page's message, serialized with `JSONSerialization`.
    let messageJSON: Data
    let sender: Sender

    /// What Chrome tells a listener about a side-panel frame: where the frame
    /// is, and nothing else. There is no `tab`, because the panel is not one,
    /// and no `id`, because the sender is a web page rather than an extension.
    struct Sender: Equatable, Sendable {
        let url: String
        let origin: String
        let frameID: Int
    }
}
