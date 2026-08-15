import Foundation

/// One `chrome.notifications.create` payload, normalized for the host.
///
/// The emulation bridge fills this in from the extension-supplied options
/// dictionary. Fields Crest cannot honor on macOS — progress bars, list items,
/// and image attachments beyond the icon — are intentionally absent rather than
/// silently accepted and dropped.
struct BrowserExtensionNotificationRequest: Equatable, Hashable, Sendable {
    /// The extension-authored identifier. Unique only within one extension.
    let identifier: String
    let title: String
    let message: String
    /// Raw bytes for the notification icon, when the extension supplied one.
    let iconData: Data?
    /// Button titles in the order the extension declared them.
    let buttonTitles: [String]

    init(
        identifier: String,
        title: String,
        message: String,
        iconData: Data? = nil,
        buttonTitles: [String] = []
    ) {
        self.identifier = identifier
        self.title = title
        self.message = message
        self.iconData = iconData
        self.buttonTitles = buttonTitles
    }
}
