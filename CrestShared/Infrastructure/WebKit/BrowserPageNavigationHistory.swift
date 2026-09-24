import Foundation
import WebKit

/// WebKit leaves some entries out of its UI-facing lists and its
/// `canGoBack`/`canGoForward` while keeping them in the session: Navigation API
/// entries even after an allowed link click, and any entry a script created
/// without user activation once the page moves off it. Keep the actual WebKit
/// items we observed, so traversal preserves document state and does not
/// reload their URLs.
///
/// - Back still uses WebKit's filter for script-created entries without a link
///   activation, which keeps a page from trapping the person behind entries it
///   added on its own.
/// - Forward offers every entry ahead of the current one that the page has
///   shown, so the page the person just left by going back stays reachable.
@MainActor
struct BrowserPageNavigationHistory {
    // MARK: - Variables

    private var entries: [WKBackForwardListItem] = []
    private var linkItems: Set<ObjectIdentifier> = []
    /// Entries that became current since the last document commit. A commit
    /// onto one of them is a new document rather than a return to history.
    private var arrivals: Set<ObjectIdentifier> = []
    private var currentIndex = 0
    private var pendingLinkURL: URL?
    private var pendingLinkSource: ObjectIdentifier?
    private(set) var backItems: [WKBackForwardListItem] = []
    private(set) var forwardItems: [WKBackForwardListItem] = []

    // MARK: - Actions - Navigation

    mutating func recordLink(to url: URL?, in list: WKBackForwardList) {
        synchronize(with: list)
        if let current = list.currentItem {
            linkItems.insert(ObjectIdentifier(current))
        }
        pendingLinkSource = list.currentItem.map(ObjectIdentifier.init)
        pendingLinkURL = url
    }

    /// A document committed. A new entry replaces the document the supplements
    /// described, and WebKit may drop the entries it omits from its lists with
    /// it, so history returns to WebKit's own list. Returning to an entry the
    /// page already showed, by going back or forward or reloading, keeps them,
    /// including the entries ahead that the person just left.
    mutating func documentDidCommit(in list: WKBackForwardList) {
        synchronize(with: list)
        defer { arrivals = [] }
        guard let current = list.currentItem, arrivals.contains(ObjectIdentifier(current)) else { return }
        self = BrowserPageNavigationHistory()
        synchronize(with: list)
    }

    mutating func synchronize(with list: WKBackForwardList) {
        guard let current = list.currentItem else { return }
        let nativeBack = list.backList
        let nativeForward = list.forwardList
        if entries.isEmpty {
            entries = nativeBack + [current] + nativeForward
            arrivals.insert(ObjectIdentifier(current))
        } else if !entries.contains(where: { $0 === current }) {
            // A new entry discards the old forward branch. A restored list may
            // contain entries we have not observed yet; seed those below too.
            entries = Array(entries.prefix(currentIndex + 1)) + [current]
            arrivals.insert(ObjectIdentifier(current))
        }
        // Merge native entries in their own order. This also seeds history
        // restored by WebKit without manufacturing entries from URL strings.
        var anchor = current
        for item in nativeBack.reversed() {
            if !entries.contains(where: { $0 === item }),
                let index = entries.firstIndex(where: { $0 === anchor })
            {
                entries.insert(item, at: index)
            }
            anchor = item
        }
        anchor = current
        for item in nativeForward {
            if !entries.contains(where: { $0 === item }),
                let index = entries.firstIndex(where: { $0 === anchor })
            {
                entries.insert(item, at: index + 1)
            }
            anchor = item
        }
        currentIndex = entries.firstIndex(where: { $0 === current }) ?? 0
        if let pendingLinkURL, pendingLinkSource != ObjectIdentifier(current) {
            if current.url == pendingLinkURL {
                linkItems.insert(ObjectIdentifier(current))
            }
            self.pendingLinkURL = nil
            pendingLinkSource = nil
        }
        // Match WebKit's bounded session list instead of retaining old items
        // after its oldest entries have been evicted.
        if entries.count > 100 {
            let removed = min(entries.count - 100, currentIndex)
            entries.removeFirst(removed)
            currentIndex -= removed
            entries = Array(entries.prefix(100))
        }
        let retained = Set(entries.map(ObjectIdentifier.init))
        linkItems.formIntersection(retained)
        arrivals.formIntersection(retained)
        let allowed = linkItems.union((nativeBack + nativeForward).map(ObjectIdentifier.init))
        backItems = entries.prefix(currentIndex).filter { allowed.contains(ObjectIdentifier($0)) }
        forwardItems = Array(entries.dropFirst(currentIndex + 1))
    }
}
