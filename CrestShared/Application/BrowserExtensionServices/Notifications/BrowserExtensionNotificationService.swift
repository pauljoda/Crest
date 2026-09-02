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

    /// How many posted notifications are remembered before the record is
    /// reconciled against what the host still has on screen.
    private static let postedRequestCapacity = 128

    private let center: any BrowserExtensionNotificationCentering
    private var subscribers: [BrowserExtensionServiceClientID: Subscribers] = [:]
    /// What each presented notification was last posted with.
    ///
    /// The host center reports which notifications are on screen but not what
    /// they say, and `chrome.notifications.update` is a partial edit that has to
    /// be merged over the previous content. This is the only record of that
    /// content, so it is kept until the notification leaves the screen — cleared
    /// by the extension, or dismissed by the person.
    private var postedRequests:
        [BrowserExtensionNotificationIdentity:
            BrowserExtensionNotificationRequest] = [:]

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
            postedRequests[identity] = request
            if postedRequests.count > Self.postedRequestCapacity {
                await prunePostedRequests()
            }
            return .presented(identity)
        } catch {
            return .rejected(description: error.localizedDescription)
        }
    }

    func update(
        _ update: BrowserExtensionNotificationUpdate,
        from client: BrowserExtensionServiceClientID
    ) async -> BrowserExtensionNotificationUpdateOutcome {
        let identity = BrowserExtensionNotificationIdentity(
            client: client,
            notificationIdentifier: update.identifier
        )
        guard let previous = postedRequests[identity] else {
            return .unknownNotification
        }
        // A notification the person dismissed from Notification Center is gone
        // as far as Chrome's `update` is concerned, so it answers `false`
        // rather than putting the notification back on screen.
        guard
            await presentedNotificationIdentifiers(for: client)
                .contains(update.identifier)
        else {
            postedRequests.removeValue(forKey: identity)
            return .unknownNotification
        }
        switch await post(update.applied(to: previous), from: client) {
        case .presented:
            return .updated
        case .authorizationDenied:
            return .authorizationDenied
        case .rejected(let description):
            return .rejected(description: description)
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
            postedRequests.removeValue(forKey: identity)
            return false
        }

        await center.removeDelivered(systemIdentifiers: [systemIdentifier])
        postedRequests.removeValue(forKey: identity)
        return true
    }

    func clearAll(from client: BrowserExtensionServiceClientID) async {
        let owned = await ownedSystemIdentifiers(for: client)
        postedRequests = postedRequests.filter { $0.key.client != client }
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

    /// Drops the content of every notification the host is no longer showing.
    ///
    /// A notification can leave the screen without an interaction the host
    /// reports — expiry, or a `Clear All` Crest never hears about — so the
    /// record is reconciled against the host once it grows past the number of
    /// notifications an extension could plausibly have on screen.
    private func prunePostedRequests() async {
        let delivered = Set(await center.deliveredSystemIdentifiers())
        postedRequests = postedRequests.filter { identity, _ in
            delivered.contains(
                BrowserExtensionNotificationIdentityCodec.systemIdentifier(
                    for: identity
                )
            )
        }
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
                .identity(fromSystemIdentifier: systemEvent.systemIdentifier)
        else {
            return
        }
        // A notification that left the screen has no content left to merge an
        // update into, and the record is dropped whether or not the extension
        // happens to be listening for the interaction.
        if case .dismissed = systemEvent.kind {
            postedRequests.removeValue(forKey: identity)
        }
        guard let continuations = subscribers[identity.client] else { return }

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
