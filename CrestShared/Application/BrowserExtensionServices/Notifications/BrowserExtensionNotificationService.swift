import Foundation

/// Routes emulated `chrome.notifications` traffic between extensions and the
/// host notification center.
///
/// The service owns every rule that the platform adapter must not know about:
/// which extension owns a given notification, whether authorization allows a
/// delivery at all, and which subscribers hear about an interaction. Presented
/// state is read back from the host rather than mirrored locally, so a
/// notification the person dismissed from Notification Center never lingers in
/// `chrome.notifications.getAll`.
@MainActor
final class BrowserExtensionNotificationService: BrowserExtensionNotificationHandling {
    private typealias Subscribers = [UUID: AsyncStream<BrowserExtensionNotificationEvent>.Continuation]

    private let center: any BrowserExtensionNotificationCentering
    private var subscribers: [BrowserExtensionServiceClientID: Subscribers] = [:]

    init(center: any BrowserExtensionNotificationCentering) {
        self.center = center
        center.setEventHandler { [weak self] systemEvent in
            self?.route(systemEvent)
        }
    }

    func requestAuthorization() async -> BrowserExtensionNotificationAuthorization {
        await center.requestAuthorization()
    }

    func currentAuthorization() async -> BrowserExtensionNotificationAuthorization {
        await center.currentAuthorization()
    }

    func post(
        _ request: BrowserExtensionNotificationRequest,
        from client: BrowserExtensionServiceClientID
    ) async -> BrowserExtensionNotificationPostOutcome {
        guard await settledAuthorization().allowsDelivery else {
            return .authorizationDenied
        }

        let identity = BrowserExtensionNotificationIdentity(
            client: client,
            notificationIdentifier: request.identifier
        )
        let delivery = BrowserExtensionNotificationDelivery(
            systemIdentifier:
                BrowserExtensionNotificationIdentityCodec
                .systemIdentifier(for: identity),
            threadIdentifier:
                BrowserExtensionNotificationIdentityCodec
                .threadIdentifier(for: client),
            categoryIdentifier:
                BrowserExtensionNotificationIdentityCodec
                .categoryIdentifier(for: identity),
            title: request.title,
            body: request.message,
            iconData: request.iconData,
            buttonTitles: request.buttonTitles
        )

        do {
            try await center.add(delivery)
            return .presented(identity)
        } catch {
            return .rejected(description: error.localizedDescription)
        }
    }

    @discardableResult
    func clear(
        notificationIdentifier: String,
        from client: BrowserExtensionServiceClientID
    ) async -> Bool {
        let identity = BrowserExtensionNotificationIdentity(
            client: client,
            notificationIdentifier: notificationIdentifier
        )
        let systemIdentifier =
            BrowserExtensionNotificationIdentityCodec
            .systemIdentifier(for: identity)
        guard await center.deliveredSystemIdentifiers().contains(systemIdentifier)
        else {
            return false
        }

        await center.removeDelivered(systemIdentifiers: [systemIdentifier])
        return true
    }

    func clearAll(from client: BrowserExtensionServiceClientID) async {
        let owned = await ownedSystemIdentifiers(for: client)
        guard !owned.isEmpty else { return }
        await center.removeDelivered(systemIdentifiers: owned)
    }

    func presentedNotificationIdentifiers(
        for client: BrowserExtensionServiceClientID
    ) async -> [String] {
        await center.deliveredSystemIdentifiers()
            .compactMap(BrowserExtensionNotificationIdentityCodec.identity(fromSystemIdentifier:))
            .filter { $0.client == client }
            .map(\.notificationIdentifier)
    }

    func events(
        for client: BrowserExtensionServiceClientID
    ) -> AsyncStream<BrowserExtensionNotificationEvent> {
        let (stream, continuation) = AsyncStream<
            BrowserExtensionNotificationEvent
        >.makeStream()
        let token = UUID()
        subscribers[client, default: [:]][token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                self?.removeSubscriber(token, for: client)
            }
        }
        return stream
    }

    private func settledAuthorization() async -> BrowserExtensionNotificationAuthorization {
        let current = await center.currentAuthorization()
        guard current == .notDetermined else { return current }
        return await center.requestAuthorization()
    }

    private func ownedSystemIdentifiers(
        for client: BrowserExtensionServiceClientID
    ) async -> [String] {
        await center.deliveredSystemIdentifiers().filter { systemIdentifier in
            BrowserExtensionNotificationIdentityCodec
                .identity(fromSystemIdentifier: systemIdentifier)?
                .client == client
        }
    }

    private func route(_ systemEvent: BrowserExtensionNotificationSystemEvent) {
        guard
            let identity =
                BrowserExtensionNotificationIdentityCodec
                .identity(fromSystemIdentifier: systemEvent.systemIdentifier),
            let continuations = subscribers[identity.client]
        else {
            return
        }

        let event = BrowserExtensionNotificationEvent(
            identity: identity,
            kind: systemEvent.kind
        )
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func removeSubscriber(
        _ token: UUID,
        for client: BrowserExtensionServiceClientID
    ) {
        subscribers[client]?.removeValue(forKey: token)
        if subscribers[client]?.isEmpty == true {
            subscribers.removeValue(forKey: client)
        }
    }
}
