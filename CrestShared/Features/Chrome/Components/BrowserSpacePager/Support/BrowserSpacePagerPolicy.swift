import SwiftUI

enum BrowserSpacePagerPolicy {
    static let showsScrollIndicators = false
    static let locksDuringContentDrag = true
    static let recentersWhenContentDragEnds = true

    @MainActor
    static var scrollIndicatorVisibility: ScrollIndicatorVisibility { .never }

    /// Whether something in flight owns the horizontal axis.
    ///
    /// Three sources, because a sidebar item can be picked up three ways and any
    /// of them is spoiled by the strip paging underneath it. The sidebar lift is
    /// named first and separately: it is the only one a touch shell ever raises,
    /// and reading the two pointer drag states alone left the pager live under
    /// every finger drag.
    static func isInteractionLocked(
        hasSidebarLift: Bool,
        hasTabDrag: Bool,
        hasFolderDrag: Bool
    ) -> Bool {
        hasSidebarLift || hasTabDrag || hasFolderDrag
    }

    static func isScrollEnabled(
        spaceCount: Int,
        isInteractionLocked: Bool
    ) -> Bool {
        spaceCount > 1 && !(locksDuringContentDrag && isInteractionLocked)
    }

    static func shouldRecenter(
        wasInteractionLocked: Bool,
        isInteractionLocked: Bool
    ) -> Bool {
        guard wasInteractionLocked != isInteractionLocked else { return false }
        return isInteractionLocked || recentersWhenContentDragEnds
    }
}
