import Foundation

/// The interaction that a delivered notification reported back.
///
/// Cases map onto `chrome.notifications.onClicked`, `onButtonClicked`, and
/// `onClosed` respectively.
enum BrowserExtensionNotificationEventKind: Equatable, Hashable, Sendable {
    case clicked
    case buttonClicked(index: Int)
    case dismissed(byUser: Bool)
}
