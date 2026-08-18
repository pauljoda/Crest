import Foundation
import UserNotifications

/// Bridges `UNUserNotificationCenterDelegate` callbacks onto the main actor.
///
/// `UNUserNotificationCenter` holds its delegate weakly and calls it from an
/// arbitrary queue, so the delegate is a shared forwarder retained independently
/// of both notification producers. The unchecked conformance is sound because
/// every stored property is main-actor isolated and only `Sendable` values cross
/// the hop.
final class BrowserExtensionNotificationSystemResponder:
    NSObject,
    UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    @MainActor static let shared = BrowserExtensionNotificationSystemResponder()

    @MainActor weak var owner: BrowserExtensionNotificationSystemCenter?
    @MainActor weak var hostedPageOwner: BrowserHostedWebNotificationSystemCenter?

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let systemIdentifier = response.notification.request.identifier
        let actionIdentifier = response.actionIdentifier
        Task { @MainActor [weak self] in
            guard let self else { return }
            if systemIdentifier.hasPrefix(
                BrowserHostedWebNotificationSystemCenter.systemIdentifierPrefix
            ) {
                hostedPageOwner?.receive(
                    systemIdentifier: systemIdentifier,
                    actionIdentifier: actionIdentifier
                )
            } else {
                owner?.receive(
                    systemIdentifier: systemIdentifier,
                    actionIdentifier: actionIdentifier
                )
            }
        }
        completionHandler()
    }

    /// Keeps extension notifications visible while Crest is frontmost. An
    /// extension usually posts *because* the person is browsing, so suppressing
    /// the banner would drop the only signal the notification carries.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
