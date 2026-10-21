import CoreGraphics
import Observation

/// What the recent tabs panel draws and how the pointer reaches the session:
/// the held session, the pictures and the stores that name each tab.
@MainActor
@Observable
final class RecentTabSwitcherModel {
    // MARK: - Variables

    var session: RecentTabSwitcherSession {
        didSet {
            guard session.isShowing, oldValue.highlightedIndex != session.highlightedIndex else { return }
            announce(spokenTitle(at: session.highlightedIndex))
        }
    }
    let browser: BrowserStore
    let snapshots: BrowserRecentTabSnapshots
    /// Commits the item at an index, as a click does.
    @ObservationIgnored var commit: @MainActor (Int) -> Void = { _ in }
    /// Tells VoiceOver which item the highlight reached.
    @ObservationIgnored var announce: @MainActor (String) -> Void = { _ in }

    /// Where each card sits in the panel's own coordinates, top left origin.
    @ObservationIgnored var cardFrames: [Int: CGRect] = [:]

    // MARK: - Initializers

    init(session: RecentTabSwitcherSession, browser: BrowserStore, snapshots: BrowserRecentTabSnapshots) {
        self.session = session
        self.browser = browser
        self.snapshots = snapshots
    }

    // MARK: - Actions - Pointer

    /// Highlights the card under `point`, in the panel's coordinates. The panel
    /// is never key, so its views get no hover of their own; its hosting view
    /// reports the pointer here.
    func pointerMoved(to point: CGPoint) {
        guard let index = cardFrames.first(where: { $0.value.contains(point) })?.key else { return }
        session.highlight(index: index)
    }

    // MARK: - Actions - Reading

    /// The tabs of `item` as the window's Space holds them, in display order.
    func tabs(of item: RecentTabItem) -> [TabStateModel] {
        guard let space = browser.shownSpace else { return [] }
        return item.tabIDs.compactMap { space.tabs.model($0) }
    }

    /// What VoiceOver says for the item at `index`.
    func spokenTitle(at index: Int) -> String {
        guard session.items.indices.contains(index) else { return "" }
        let title = tabs(of: session.items[index]).map(\.shownTitle).joined(separator: ", ")
        return String(localized: "\(title), \(index + 1) of \(session.items.count)")
    }
}
