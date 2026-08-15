import Foundation
import UserNotifications

/// Bridges `UNUserNotificationCenterDelegate` callbacks onto the main actor.
///
/// `UNUserNotificationCenter` holds its delegate weakly and calls it from an
/// arbitrary queue, so the delegate is a small forwarder retained by
/// ``BrowserExtensionNotificationSystemCenter`` rather than the center itself.
/// The unchecked conformance is sound because every stored property is
/// main-actor isolated and only `Sendable` values cross the hop.
final class BrowserExtensionNotificationSystemResponder:
    NSObject,
    UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    @MainActor weak var owner: BrowserExtensionNotificationSystemCenter?

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let systemIdentifier = response.notification.request.identifier
        let actionIdentifier = response.actionIdentifier
        Task { @MainActor [weak self] in
            self?.owner?.receive(
                systemIdentifier: systemIdentifier,
                actionIdentifier: actionIdentifier
            )
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
