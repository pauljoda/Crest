import Foundation

/// Delivers notices to the window the person is looking at, for callers that
/// do not hold a window's notices: engine toasts, extension actions, page
/// services, Settings. The window registered most recently stands in when
/// none is focused.
@MainActor
final class BrowserNoticeCenter {
    // MARK: - Static Variables

    static let shared = BrowserNoticeCenter()

    // MARK: - Types

    private struct Receiver {
        weak var notices: BrowserNotices?
        let isFocused: @MainActor () -> Bool
    }

    // MARK: - Variables

    private var receivers: [Receiver] = []

    // MARK: - Actions - Receivers

    /// Lets a window's `notices` show what callers post while `isFocused`
    /// holds. Registering again makes the window the one that stands in.
    func register(_ notices: BrowserNotices, isFocused: @escaping @MainActor () -> Bool) {
        receivers.removeAll { $0.notices == nil || $0.notices === notices }
        receivers.append(Receiver(notices: notices, isFocused: isFocused))
    }

    // MARK: - Actions - Posting

    /// Shows `notice` in the window the person is looking at, and answers
    /// that window's notices, which can put it away early.
    @discardableResult
    func post(_ notice: BrowserNotice) -> BrowserNotices? {
        receivers.removeAll { $0.notices == nil }
        let target = (receivers.last(where: { $0.isFocused() }) ?? receivers.last)?.notices
        target?.show(notice)
        return target
    }
}
