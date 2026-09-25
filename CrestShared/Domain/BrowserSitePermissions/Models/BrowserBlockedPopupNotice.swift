import Foundation

struct BrowserBlockedPopupNotice: Equatable, Sendable {
    let origin: SiteOrigin
    let status: BlockedPopupStatus
}

/// Document-scoped state for the one blocked-popup indication a page may show.
///
/// The content bridge coalesces before crossing into native code, and the
/// core's notice rules are the second boundary: even a hostile page posting
/// directly to the bridge cannot stack indicators or accessibility
/// announcements in one document. Each mutation reports whether it changed
/// anything; a core that cannot answer changes nothing.
struct BrowserBlockedPopupPageState: Equatable, Sendable {
    private(set) var notice: BrowserBlockedPopupNotice?
    private(set) var documentIdentifier: String?
    private(set) var indicationRevision = 0

    init() {}

    init(notice: BrowserBlockedPopupNotice?, documentIdentifier: String?, indicationRevision: Int) {
        self.notice = notice
        self.documentIdentifier = documentIdentifier
        self.indicationRevision = indicationRevision
    }

    @discardableResult
    mutating func recordBlockedAttempt(documentIdentifier: String, origin: SiteOrigin) -> Bool {
        apply(.blocked, documentIdentifier: documentIdentifier, origin: origin)
    }

    @discardableResult
    mutating func recordPermissionAllowed() -> Bool { apply(.permissionAllowed) }

    @discardableResult
    mutating func recordPermissionBlockedAgain() -> Bool { apply(.permissionBlockedAgain) }

    @discardableResult
    mutating func clearForNavigation() -> Bool { apply(.navigation) }

    @discardableResult
    mutating func clearAfterAllowedPopup() -> Bool { apply(.popupAllowed) }

    private mutating func apply(_ event: BlockedPopupEvent, documentIdentifier: String? = nil,
        origin: SiteOrigin? = nil) -> Bool {
        guard let next = BrowserCorePolicy.blockedPopupState(after: event, from: self,
            documentIdentifier: documentIdentifier, origin: origin) else { return false }
        self = next
        return true
    }
}
