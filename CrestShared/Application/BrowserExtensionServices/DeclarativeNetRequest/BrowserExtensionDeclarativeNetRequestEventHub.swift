import Foundation

/// Fan-out for emulated header-rule changes.
///
/// A rule table belongs to one extension in one Space, so — unlike the tab
/// group hub, whose subject is browser-wide — an event is published to one
/// client. Every context of that extension holds its own watch port, so one
/// client can have several subscribers and all of them receive the change.
@MainActor
final class BrowserExtensionDeclarativeNetRequestEventHub {
    private var subscribers:
        [BrowserExtensionServiceClientID: [UUID: AsyncStream<
            BrowserExtensionEmulatedHeaderRulesets
        >.Continuation]] = [:]

    func events(for client: BrowserExtensionServiceClientID)
        -> AsyncStream<BrowserExtensionEmulatedHeaderRulesets>
    {
        let (stream, continuation) = AsyncStream<BrowserExtensionEmulatedHeaderRulesets>
            .makeStream()
        let token = UUID()
        subscribers[client, default: [:]][token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.subscribers[client]?[token] = nil }
        }
        return stream
    }

    func publish(
        _ rulesets: BrowserExtensionEmulatedHeaderRulesets,
        to client: BrowserExtensionServiceClientID
    ) {
        for subscriber in subscribers[client]?.values ?? [:].values {
            subscriber.yield(rulesets)
        }
    }

    func remove(client: BrowserExtensionServiceClientID) {
        let removed = subscribers.removeValue(forKey: client)
        for subscriber in removed?.values ?? [:].values { subscriber.finish() }
    }
}
