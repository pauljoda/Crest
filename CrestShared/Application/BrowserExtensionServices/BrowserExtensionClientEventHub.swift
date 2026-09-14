import Foundation

/// Owns stream lifetimes for an extension's contexts within one Space.
/// Callers decide which clients may receive each event.
@MainActor
final class BrowserExtensionClientEventHub<Event: Sendable> {
    private var subscribers: [BrowserExtensionServiceClientID: [UUID: AsyncStream<Event>.Continuation]] = [:]

    func events(for client: BrowserExtensionServiceClientID) -> AsyncStream<Event> {
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        let token = UUID()
        subscribers[client, default: [:]][token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.subscribers[client]?[token] = nil }
        }
        return stream
    }

    func publish(_ event: Event, to client: BrowserExtensionServiceClientID) {
        for subscriber in subscribers[client]?.values ?? [:].values { subscriber.yield(event) }
    }

    func publish(_ event: Event, to clients: some Sequence<BrowserExtensionServiceClientID>) {
        for client in clients { publish(event, to: client) }
    }

    func remove(client: BrowserExtensionServiceClientID) {
        let removed = subscribers.removeValue(forKey: client)
        for subscriber in removed?.values ?? [:].values { subscriber.finish() }
    }
}
