import Foundation

/// Framework-neutral projection of the host notification authorization state.
///
/// `chrome.notifications.create` has no authorization concept of its own, so the
/// emulation layer maps Crest's own system authorization onto a posting outcome
/// rather than surfacing a separate permission prompt to extension code.
enum BrowserExtensionNotificationAuthorization: Equatable, Hashable, Sendable {
    case notDetermined
    case authorized
    case denied

    /// Whether a delivery attempt can reach the notification center.
    var allowsDelivery: Bool {
        self == .authorized
    }
}

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

/// One `chrome.notifications.update` payload: the fields the extension actually
/// supplied, and nothing more.
///
/// Chrome's `update` is a partial edit — an omitted option keeps whatever the
/// notification is already showing — so an absent field here means "keep" and
/// never "clear". That distinction cannot be expressed by a
/// ``BrowserExtensionNotificationRequest``, whose fields are all present by
/// construction, which is why the merge takes this type instead.
struct BrowserExtensionNotificationUpdate: Equatable, Hashable, Sendable {
    /// The extension-authored identifier of the notification being edited.
    let identifier: String
    let title: String?
    let message: String?
    /// Button titles in the order the extension declared them, when the update
    /// restated the buttons at all.
    let buttonTitles: [String]?

    init(
        identifier: String,
        title: String? = nil,
        message: String? = nil,
        buttonTitles: [String]? = nil
    ) {
        self.identifier = identifier
        self.title = title
        self.message = message
        self.buttonTitles = buttonTitles
    }

    /// `request` with every supplied field overwritten and the rest untouched.
    ///
    /// The identifier comes from `request`: an update addresses a notification
    /// that already exists and cannot rename it.
    func applied(
        to request: BrowserExtensionNotificationRequest
    ) -> BrowserExtensionNotificationRequest {
        BrowserExtensionNotificationRequest(
            identifier: request.identifier,
            title: title ?? request.title,
            message: message ?? request.message,
            iconData: request.iconData,
            buttonTitles: buttonTitles ?? request.buttonTitles
        )
    }
}

/// The result of an update attempt.
///
/// ``unknownNotification`` is the answer Chrome gives for an identifier the
/// extension no longer has on screen: `update` reports `false` rather than
/// quietly creating a notification the extension never asked to re-post.
enum BrowserExtensionNotificationUpdateOutcome: Equatable, Hashable, Sendable {
    case updated
    case unknownNotification
    case authorizationDenied
    case rejected(description: String)
}

/// A notification resolved down to the flat identifiers and content the host
/// notification center needs.
///
/// Every extension-facing concern — identity encoding, authorization gating,
/// per-client bookkeeping — has already been applied by the time a delivery
/// reaches ``BrowserExtensionNotificationCentering``, which keeps the platform
/// adapter free of routing rules.
struct BrowserExtensionNotificationDelivery: Equatable, Hashable, Sendable {
    let systemIdentifier: String
    let threadIdentifier: String
    let categoryIdentifier: String
    let title: String
    let body: String
    let iconData: Data?
    let buttonTitles: [String]
}

/// The result of a posting attempt.
///
/// A denied authorization is an ordinary outcome rather than an error: an
/// extension that calls `chrome.notifications.create` while Crest itself is
/// muted in System Settings should receive a quiet negative answer, not a
/// rejected promise that its background script is unlikely to handle.
enum BrowserExtensionNotificationPostOutcome: Equatable, Hashable, Sendable {
    case presented(BrowserExtensionNotificationIdentity)
    case authorizationDenied
    case rejected(description: String)

    /// The identity the host accepted, when the notification was presented.
    var presentedIdentity: BrowserExtensionNotificationIdentity? {
        guard case .presented(let identity) = self else { return nil }
        return identity
    }
}
