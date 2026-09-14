import Foundation

/// Keeps visual changes and membership changes on separate streams.
///
/// The one difference is deliberate: a sidebar event belongs to the extension
/// that owns the panel, so it is published *to* a client. A group belongs to
/// the browser, so `publish` takes the clients that share its Space and
/// delivers the same event to all of them.
@MainActor
final class BrowserExtensionTabGroupEventHub {
    private let events = BrowserExtensionClientEventHub<BrowserExtensionTabGroupEvent>()
    private let membership = BrowserExtensionClientEventHub<BrowserExtensionTabGroupEvent.Membership>()

    func membershipEvents(for client: BrowserExtensionServiceClientID)
        -> AsyncStream<BrowserExtensionTabGroupEvent.Membership>
    {
        membership.events(for: client)
    }

    func publishMembership(
        _ event: BrowserExtensionTabGroupEvent.Membership,
        to clients: some Sequence<BrowserExtensionServiceClientID>
    ) {
        membership.publish(event, to: clients)
    }

    func events(for client: BrowserExtensionServiceClientID)
        -> AsyncStream<BrowserExtensionTabGroupEvent>
    {
        events.events(for: client)
    }

    func publish(
        _ event: BrowserExtensionTabGroupEvent, to clients: some Sequence<BrowserExtensionServiceClientID>
    ) {
        events.publish(event, to: clients)
    }

    func remove(client: BrowserExtensionServiceClientID) {
        events.remove(client: client)
        membership.remove(client: client)
    }
}
