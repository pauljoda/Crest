import Foundation

/// Carries a web page's `runtime.sendMessage` into an extension and its answer
/// back out again.
///
/// A delivery is fanned out to every `runtime.watch` port the extension has
/// open in the Space and completes on the first reply that names its request.
/// Nothing here decides whether the page was allowed to send: that gate lives
/// with the relay, which owns the frame's URL.
///
/// Every wait is bounded. An extension whose worker was evicted mid-dispatch,
/// or one that registered a listener and never answers, would otherwise leave
/// the page's promise pending for the life of the panel; Chrome ends that with
/// "Could not establish connection", and so does a `nil` answer here.
@MainActor
final class BrowserExtensionExternalMessageRegistry:
    BrowserExtensionExternalMessageHandling
{
    static let defaultReplyTimeout = Duration.seconds(30)

    private final class PendingReply {
        let client: BrowserExtensionServiceClientID
        let continuation: CheckedContinuation<Data?, Never>
        var expiry: Task<Void, Never>?

        init(
            client: BrowserExtensionServiceClientID,
            continuation: CheckedContinuation<Data?, Never>
        ) {
            self.client = client
            self.continuation = continuation
        }
    }

    private var subscribers:
        [BrowserExtensionServiceClientID: [UUID: AsyncStream<BrowserExtensionExternalMessageDelivery>
            .Continuation]] = [:]
    private var pendingReplies: [String: PendingReply] = [:]
    private let replyTimeout: Duration
    private let makeRequestID: () -> String

    init(
        replyTimeout: Duration = BrowserExtensionExternalMessageRegistry
            .defaultReplyTimeout,
        makeRequestID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.replyTimeout = replyTimeout
        self.makeRequestID = makeRequestID
    }

    func events(
        for client: BrowserExtensionServiceClientID
    ) -> AsyncStream<BrowserExtensionExternalMessageDelivery> {
        let (stream, continuation) = AsyncStream<
            BrowserExtensionExternalMessageDelivery
        >.makeStream()
        let token = UUID()
        subscribers[client, default: [:]][token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.subscribers[client]?[token] = nil
            }
        }
        return stream
    }

    /// Whether any context of this extension is listening. A page that reaches
    /// an extension with no `onMessageExternal` listener gets Chrome's
    /// "receiving end does not exist" without a 30-second wait for it.
    func hasWatchers(for client: BrowserExtensionServiceClientID) -> Bool {
        !(subscribers[client]?.isEmpty ?? true)
    }

    /// Delivers `messageJSON` and answers with the extension's reply, or `nil`
    /// when nobody was listening, nobody claimed the message, or the reply did
    /// not arrive in time.
    func deliver(
        messageJSON: Data,
        sender: BrowserExtensionExternalMessageDelivery.Sender,
        to client: BrowserExtensionServiceClientID
    ) async -> Data? {
        guard let ports = subscribers[client], !ports.isEmpty else {
            return nil
        }
        let requestID = makeRequestID()
        let delivery = BrowserExtensionExternalMessageDelivery(
            requestID: requestID,
            messageJSON: messageJSON,
            sender: sender
        )
        return await withCheckedContinuation { continuation in
            let pending = PendingReply(
                client: client,
                continuation: continuation
            )
            pendingReplies[requestID] = pending
            pending.expiry = Task { @MainActor [weak self, replyTimeout] in
                try? await Task.sleep(for: replyTimeout)
                guard !Task.isCancelled else { return }
                self?.resolve(requestID: requestID, responseJSON: nil)
            }
            for port in ports.values {
                port.yield(delivery)
            }
        }
    }

    /// Completes the delivery `requestID` names. `false` when no delivery is
    /// waiting — a second context answering after the first, or a reply that
    /// arrived past the timeout.
    @discardableResult
    func resolve(requestID: String, responseJSON: Data?) -> Bool {
        guard let pending = pendingReplies.removeValue(forKey: requestID) else {
            return false
        }
        pending.expiry?.cancel()
        pending.continuation.resume(returning: responseJSON)
        return true
    }

    /// Drops this extension's ports and ends every delivery still waiting on
    /// them. A context that unloads takes its listeners with it, so the page
    /// hears "receiving end does not exist" now rather than after the timeout.
    func unregister(client: BrowserExtensionServiceClientID) {
        let removed = subscribers.removeValue(forKey: client)
        for port in removed?.values ?? [:].values {
            port.finish()
        }
        for requestID in pendingReplies.filter({ $0.value.client == client })
            .keys
        {
            resolve(requestID: requestID, responseJSON: nil)
        }
    }
}
