import Foundation

struct BrowserBlockedPopupNotice: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case blocked
        case allowedAwaitingRetry
    }

    let origin: BrowserSiteOrigin
    let status: Status
}

/// Document-scoped state for the one blocked-popup indication a page may show.
///
/// The content bridge coalesces before crossing into native code, and this state
/// machine is the second boundary: even a hostile page posting directly to the
/// bridge cannot stack indicators or accessibility announcements in one document.
struct BrowserBlockedPopupPageState: Equatable, Sendable {
    private(set) var notice: BrowserBlockedPopupNotice?
    private(set) var documentIdentifier: String?
    private(set) var indicationRevision = 0

    @discardableResult
    mutating func recordBlockedAttempt(
        documentIdentifier: String,
        origin: BrowserSiteOrigin
    ) -> Bool {
        guard notice == nil else { return false }
        self.documentIdentifier = documentIdentifier
        notice = BrowserBlockedPopupNotice(origin: origin, status: .blocked)
        indicationRevision &+= 1
        return true
    }

    @discardableResult
    mutating func recordPermissionAllowed() -> Bool {
        guard let notice, notice.status == .blocked else { return false }
        self.notice = BrowserBlockedPopupNotice(
            origin: notice.origin,
            status: .allowedAwaitingRetry
        )
        return true
    }

    @discardableResult
    mutating func recordPermissionBlockedAgain() -> Bool {
        guard let notice, notice.status == .allowedAwaitingRetry else {
            return false
        }
        self.notice = BrowserBlockedPopupNotice(
            origin: notice.origin,
            status: .blocked
        )
        return true
    }

    @discardableResult
    mutating func clearForNavigation() -> Bool {
        guard notice != nil || documentIdentifier != nil else { return false }
        notice = nil
        documentIdentifier = nil
        return true
    }

    @discardableResult
    mutating func clearAfterAllowedPopup() -> Bool {
        guard notice?.status == .allowedAwaitingRetry else { return false }
        notice = nil
        documentIdentifier = nil
        return true
    }
}
