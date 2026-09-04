import Foundation

@MainActor
final class BrowserExtensionDebuggerEventHub {
    private var subscribers:
        [BrowserExtensionServiceClientID: [UUID: AsyncStream<BrowserExtensionDebuggerEvent>.Continuation]] = [:]

    func events(for client: BrowserExtensionServiceClientID) -> AsyncStream<BrowserExtensionDebuggerEvent> {
        let (stream, continuation) = AsyncStream<BrowserExtensionDebuggerEvent>.makeStream()
        let token = UUID()
        subscribers[client, default: [:]][token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.subscribers[client]?[token] = nil }
        }
        return stream
    }

    func publish(_ event: BrowserExtensionDebuggerEvent, to client: BrowserExtensionServiceClientID) {
        for subscriber in subscribers[client]?.values ?? [:].values { subscriber.yield(event) }
    }

    func remove(client: BrowserExtensionServiceClientID) {
        let removed = subscribers.removeValue(forKey: client)
        for subscriber in removed?.values ?? [:].values { subscriber.finish() }
    }
}
