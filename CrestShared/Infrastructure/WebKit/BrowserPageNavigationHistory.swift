import Foundation
import WebKit

/// WebKit can omit Navigation API entries from its UI-facing lists even after
/// an allowed link click. Keep the actual WebKit items we observed for those
/// links, so traversal preserves document state and does not reload their URLs.
/// Script-created entries without a link activation still use WebKit's filter.
@MainActor
struct BrowserPageNavigationHistory {
    private var entries: [WKBackForwardListItem] = []
    private var currentIndex = 0
    private var linkItems: Set<ObjectIdentifier> = []
    private var pendingLinkURL: URL?
    private var pendingLinkSource: ObjectIdentifier?
    private(set) var backItems: [WKBackForwardListItem] = []
    private(set) var forwardItems: [WKBackForwardListItem] = []

    mutating func recordLink(to url: URL?, in list: WKBackForwardList) {
        synchronize(with: list)
        if let current = list.currentItem {
            linkItems.insert(ObjectIdentifier(current))
        }
        pendingLinkSource = list.currentItem.map(ObjectIdentifier.init)
        pendingLinkURL = url
    }

    mutating func synchronize(with list: WKBackForwardList) {
        guard let current = list.currentItem else { return }
        let nativeBack = list.backList
        let nativeForward = list.forwardList
        if entries.isEmpty {
            entries = nativeBack + [current] + nativeForward
        } else if !entries.contains(where: { $0 === current }) {
            // A new entry discards the old forward branch. A restored list may
            // contain entries we have not observed yet; seed those below too.
            entries = Array(entries.prefix(currentIndex + 1)) + [current]
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
        linkItems.formIntersection(Set(entries.map(ObjectIdentifier.init)))
        let allowed = linkItems.union((nativeBack + nativeForward).map(ObjectIdentifier.init))
        backItems = entries.prefix(currentIndex).filter { allowed.contains(ObjectIdentifier($0)) }
        forwardItems = entries.dropFirst(currentIndex + 1).filter { allowed.contains(ObjectIdentifier($0)) }
    }
}
