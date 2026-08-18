import Foundation
import UserNotifications

/// macOS adapter that carries emulated extension notifications to
/// `UNUserNotificationCenter`.
///
/// Buttons force a per-notification category: `UNNotificationAction`s are
/// declared on categories, not on requests, and every extension notification
/// may carry a different set of buttons. Categories are therefore registered
/// under the identity-derived category identifier and withdrawn together with
/// the notification, which keeps the registered set bounded by what is actually
/// on screen.
@MainActor
final class BrowserExtensionNotificationSystemCenter:
    BrowserExtensionNotificationCentering
{
    private static let buttonActionSeparator = ".button."

    private let center: UNUserNotificationCenter
    private let responder = BrowserExtensionNotificationSystemResponder.shared
    private var categories: [String: UNNotificationCategory] = [:]
    private var eventHandler: ((BrowserExtensionNotificationSystemEvent) -> Void)?

    init(center: UNUserNotificationCenter) {
        self.center = center
        responder.owner = self
        center.delegate = responder
    }

    func currentAuthorization() async -> BrowserExtensionNotificationAuthorization {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(
                    returning: Self.authorization(from: settings.authorizationStatus)
                )
            }
        }
    }

    func requestAuthorization() async -> BrowserExtensionNotificationAuthorization {
        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            return granted ? .authorized : .denied
        } catch {
            return await currentAuthorization()
        }
    }

    func add(_ delivery: BrowserExtensionNotificationDelivery) async throws {
        registerCategory(for: delivery)

        let content = UNMutableNotificationContent()
        content.title = delivery.title
        content.body = delivery.body
        content.threadIdentifier = delivery.threadIdentifier
        content.categoryIdentifier = delivery.categoryIdentifier
        if let attachment = iconAttachment(for: delivery) {
            content.attachments = [attachment]
        }

        try await center.add(
            UNNotificationRequest(
                identifier: delivery.systemIdentifier,
                content: content,
                trigger: nil
            )
        )
    }

    func removeDelivered(systemIdentifiers: [String]) async {
        center.removeDeliveredNotifications(withIdentifiers: systemIdentifiers)
        let withdrawn = Set(
            systemIdentifiers.compactMap { systemIdentifier in
                BrowserExtensionNotificationIdentityCodec
                    .identity(fromSystemIdentifier: systemIdentifier)
                    .map(
                        BrowserExtensionNotificationIdentityCodec
                            .categoryIdentifier(for:)
                    )
            }
        )
        guard !withdrawn.isEmpty else { return }
        categories = categories.filter { !withdrawn.contains($0.key) }
        center.setNotificationCategories(Set(categories.values))
    }

    func deliveredSystemIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(
                    returning: notifications.map(\.request.identifier)
                )
            }
        }
    }

    func setEventHandler(
        _ handler: @escaping @MainActor (BrowserExtensionNotificationSystemEvent) -> Void
    ) {
        eventHandler = handler
    }

    /// Called by ``BrowserExtensionNotificationSystemResponder`` once the
    /// delegate callback has hopped onto the main actor.
    func receive(systemIdentifier: String, actionIdentifier: String) {
        guard let kind = Self.eventKind(for: actionIdentifier) else { return }
        eventHandler?(
            BrowserExtensionNotificationSystemEvent(
                systemIdentifier: systemIdentifier,
                kind: kind
            )
        )
    }

    private func registerCategory(
        for delivery: BrowserExtensionNotificationDelivery
    ) {
        let actions = delivery.buttonTitles.enumerated().map { index, title in
            UNNotificationAction(
                identifier: Self.actionIdentifier(
                    category: delivery.categoryIdentifier,
                    buttonIndex: index
                ),
                title: title,
                options: []
            )
        }
        categories[delivery.categoryIdentifier] = UNNotificationCategory(
            identifier: delivery.categoryIdentifier,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories(Set(categories.values))
    }

    /// Writes the icon somewhere `UNNotificationAttachment` can adopt it.
    ///
    /// A failure here is deliberately non-fatal: an extension that supplies an
    /// unreadable icon should still get its text notification.
    private func iconAttachment(
        for delivery: BrowserExtensionNotificationDelivery
    ) -> UNNotificationAttachment? {
        guard let iconData = delivery.iconData, !iconData.isEmpty else {
            return nil
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crest-extension-notifications", isDirectory: true)
        let fileURL = directory.appendingPathComponent(
            "\(UUID().uuidString).png",
            isDirectory: false
        )

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try iconData.write(to: fileURL, options: .atomic)
            return try UNNotificationAttachment(
                identifier: fileURL.lastPathComponent,
                url: fileURL,
                options: nil
            )
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    private static func actionIdentifier(
        category: String,
        buttonIndex: Int
    ) -> String {
        "\(category)\(buttonActionSeparator)\(buttonIndex)"
    }

    private static func eventKind(
        for actionIdentifier: String
    ) -> BrowserExtensionNotificationEventKind? {
        switch actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            return .clicked
        case UNNotificationDismissActionIdentifier:
            return .dismissed(byUser: true)
        default:
            guard
                let separator = actionIdentifier.range(
                    of: buttonActionSeparator,
                    options: .backwards
                ),
                let index = Int(actionIdentifier[separator.upperBound...])
            else {
                return nil
            }
            return .buttonClicked(index: index)
        }
    }

    nonisolated private static func authorization(
        from status: UNAuthorizationStatus
    ) -> BrowserExtensionNotificationAuthorization {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }
}
