import Foundation

@MainActor
final class BrowserExtensionSidebarEventHub {
    private var subscribers:
        [BrowserExtensionServiceClientID: [UUID: AsyncStream<BrowserExtensionSidebarEvent>.Continuation]] = [:]

    func events(for client: BrowserExtensionServiceClientID) -> AsyncStream<BrowserExtensionSidebarEvent> {
        let (stream, continuation) = AsyncStream<BrowserExtensionSidebarEvent>.makeStream()
        let token = UUID()
        subscribers[client, default: [:]][token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.subscribers[client]?[token] = nil }
        }
        return stream
    }

    func publish(_ event: BrowserExtensionSidebarEvent, to client: BrowserExtensionServiceClientID) {
        for subscriber in subscribers[client]?.values ?? [:].values { subscriber.yield(event) }
    }

    func remove(client: BrowserExtensionServiceClientID) {
        let removed = subscribers.removeValue(forKey: client)
        for subscriber in removed?.values ?? [:].values { subscriber.finish() }
    }
}
