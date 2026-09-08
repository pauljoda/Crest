import Foundation

/// In-memory notification center used by tests, previews, and isolated
/// launches.
///
/// It keeps the deliveries it accepted so callers can assert on the exact
/// identifiers, thread grouping, and button titles the service produced, and it
/// can replay interactions through ``simulate(_:)`` without a real notification
/// ever being presented.
@MainActor
final class InMemoryBrowserExtensionNotificationCenter:
    BrowserExtensionNotificationCentering
{
    /// The state ``currentAuthorization()`` reports. Tests set this directly.
    var authorization: BrowserExtensionNotificationAuthorization
    /// The state a prompt settles on when the current state is undetermined.
    var authorizationAfterPrompt: BrowserExtensionNotificationAuthorization
    /// When set, the next ``add(_:)`` throws it instead of accepting.
    var addFailure: (any Error)?

    private(set) var deliveries: [BrowserExtensionNotificationDelivery] = []
    private(set) var authorizationPromptCount = 0
    private var eventHandler: ((BrowserExtensionNotificationSystemEvent) -> Void)?

    init(
        authorization: BrowserExtensionNotificationAuthorization = .authorized,
        authorizationAfterPrompt: BrowserExtensionNotificationAuthorization = .authorized
    ) {
        self.authorization = authorization
        self.authorizationAfterPrompt = authorizationAfterPrompt
    }

    func currentAuthorization() async -> BrowserExtensionNotificationAuthorization {
        authorization
    }

    func requestAuthorization() async -> BrowserExtensionNotificationAuthorization {
        authorizationPromptCount += 1
        if authorization == .notDetermined {
            authorization = authorizationAfterPrompt
        }
        return authorization
    }

    func add(_ delivery: BrowserExtensionNotificationDelivery) async throws {
        if let addFailure {
            self.addFailure = nil
            throw addFailure
        }
        deliveries.removeAll { $0.systemIdentifier == delivery.systemIdentifier }
        deliveries.append(delivery)
    }

    func removeDelivered(systemIdentifiers: [String]) async {
        let withdrawn = Set(systemIdentifiers)
        deliveries.removeAll { withdrawn.contains($0.systemIdentifier) }
    }

    func deliveredSystemIdentifiers() async -> [String] {
        deliveries.map(\.systemIdentifier)
    }

    func setEventHandler(
        _ handler: @escaping @MainActor (BrowserExtensionNotificationSystemEvent) -> Void
    ) {
        eventHandler = handler
    }

    /// Replays an interaction as though the host had reported it.
    func simulate(_ event: BrowserExtensionNotificationSystemEvent) {
        eventHandler?(event)
    }

    /// The delivery recorded for `systemIdentifier`, if it is still presented.
    func delivery(
        withSystemIdentifier systemIdentifier: String
    ) -> BrowserExtensionNotificationDelivery? {
        deliveries.first { $0.systemIdentifier == systemIdentifier }
    }
}
