import Foundation

/// Which presented split cards memory pressure is allowed to take back.
///
/// Presented cards are ineligible by design on both platforms: unloading a web
/// view somebody is looking at is never a saving worth making. iOS keeps one
/// narrow exception, and only at `.critical`. A four-member group in a small
/// session can leave the store holding nothing *but* presented pages, and a
/// store with nothing to give hands the system a termination instead of a
/// reclaim — which costs the person every card rather than one.
///
/// Even then the focused card and its two immediate neighbours stay resident:
/// those are exactly the cards one toolbar swipe can reach, so evicting them
/// would trade a background page for a blank placeholder under the very next
/// gesture. Anything further out is off screen, more than a swipe away, and
/// restored by `prepareResidentPage` the moment the carousel approaches it.
enum BrowserPresentedPageReleasePolicy {
    /// How far from the focused card a presented member must sit before critical
    /// pressure may reclaim it.
    static let protectedNeighbourDistance = 1

    /// The presented members that become eviction candidates, in the order they
    /// were handed in — the caller sorts by idle time, so passing an
    /// already-ordered list keeps the fallback least-recently-used first.
    ///
    /// Answers nothing at all unless pressure is critical *and* the ordinary
    /// off-screen sweep found nobody, so the common path never reaches a
    /// presented page.
    static func fallbackReleasableTabIDs(
        presentedTabIDs: [TabID],
        focusedTabID: TabID?,
        level: BrowserMemoryPressureLevel,
        hasOtherReleasablePages: Bool
    ) -> [TabID] {
        guard level == .critical,
            !hasOtherReleasablePages,
            let focusedTabID,
            let focusedIndex = presentedTabIDs.firstIndex(of: focusedTabID)
        else { return [] }
        return presentedTabIDs.enumerated().compactMap { index, tabID in
            let distance = abs(index - focusedIndex)
            return distance > protectedNeighbourDistance ? tabID : nil
        }
    }
}
