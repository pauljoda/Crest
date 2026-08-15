import SwiftUI

/// How the iPhone carousel pages between the cards of a split.
enum MobileSplitCardPagerPolicy {
    /// Whether a finger on the page may page the carousel.
    ///
    /// `false` for 0.4, and the pager is `scrollDisabled` because of it. A
    /// horizontal `ScrollView` wrapped around live `WKWebView`s competes with
    /// every page's own horizontal pan — carousels, maps, code blocks, and
    /// WebKit's own back/forward edge swipe — and the loser of that arbitration
    /// is whichever one the person actually meant. Paging is therefore
    /// programmatic: the toolbar swipe commits a selection and the pager
    /// animates to it. Direct content-drag paging is a post-0.4 gesture spike.
    static let allowsDirectDrag = false

    static let showsScrollIndicators = false

    @MainActor
    static var scrollIndicatorVisibility: ScrollIndicatorVisibility { .never }

    /// Whether a presented run is long enough to page at all. A run of one is a
    /// plain tab and renders through the ordinary single-page path.
    static func isPagerPresented(memberCount: Int) -> Bool {
        memberCount >= BrowserSplitGroupPolicy.minimumRenderableMembers
    }

    /// The card one step from `tabID`, clamped at both ends.
    ///
    /// Deliberately not wrapping. A swipe is a spatial gesture — the cards sit in
    /// a row — so running off the end and reappearing at the other would read as
    /// the carousel losing its place. The keyboard's focus-cycling commands do
    /// wrap, because a repeated chord is a cycle rather than a direction.
    static func adjacentMember(
        of tabID: TabID,
        in members: [TabID],
        direction: BrowserSpaceSwipeDirection
    ) -> TabID? {
        guard let index = members.firstIndex(of: tabID) else { return nil }
        let target = direction == .next ? index + 1 : index - 1
        guard members.indices.contains(target) else { return nil }
        return members[target]
    }
}
