import SwiftUI

enum BrowserSpacePagerPolicy {
    static let showsScrollIndicators = false
    static let locksDuringContentDrag = true
    static let recentersWhenContentDragEnds = true

    @MainActor
    static var scrollIndicatorVisibility: ScrollIndicatorVisibility { .never }

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
