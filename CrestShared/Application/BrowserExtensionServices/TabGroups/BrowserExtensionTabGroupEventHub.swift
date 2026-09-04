import Foundation

/// Fan-out for tab-group events, shaped like the sidebar hub.
///
/// The one difference is deliberate: a sidebar event belongs to the extension
/// that owns the panel, so it is published *to* a client. A group belongs to
/// the browser, so `publish` takes the clients that share its Space and
/// delivers the same event to all of them.
@MainActor
final class BrowserExtensionTabGroupEventHub {
    private var subscribers:
        [BrowserExtensionServiceClientID: [UUID: AsyncStream<BrowserExtensionTabGroupEvent>.Continuation]] =
            [:]

    func events(for client: BrowserExtensionServiceClientID)
        -> AsyncStream<BrowserExtensionTabGroupEvent>
    {
        let (stream, continuation) = AsyncStream<BrowserExtensionTabGroupEvent>.makeStream()
        let token = UUID()
        subscribers[client, default: [:]][token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.subscribers[client]?[token] = nil }
        }
        return stream
    }

    func publish(
        _ event: BrowserExtensionTabGroupEvent, to clients: some Sequence<BrowserExtensionServiceClientID>
    ) {
        for client in clients {
            for subscriber in subscribers[client]?.values ?? [:].values { subscriber.yield(event) }
        }
    }

    func remove(client: BrowserExtensionServiceClientID) {
        let removed = subscribers.removeValue(forKey: client)
        for subscriber in removed?.values ?? [:].values { subscriber.finish() }
    }
}
