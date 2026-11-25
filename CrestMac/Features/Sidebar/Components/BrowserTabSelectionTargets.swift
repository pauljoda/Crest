import SwiftUI

/// The sidebar rows, pinned tiles and folder headers that take a selection
/// click, where each one is now, so the selection monitor can find the one a
/// click lands on.
///
/// Each target registers its live frame as it lays out, never the resting
/// frame a drag freezes, in SwiftUI's global space of its window. A target in
/// a scrolling list counts only where the list shows it: the part of a row
/// the list has scrolled under its edge takes no click, as a clipped view
/// takes none.
///
/// A frame rather than a view of its own per target: an AppKit view in every
/// row made each row slower to build as the sidebar scrolled it into view.
@MainActor
final class BrowserTabSelectionTargets {
    // MARK: - Types

    /// One target's item and where it is.
    struct Target {
        let itemID: BrowserSelectionItemID
        weak var browser: BrowserStore?
        let assignment: BrowserSpaceRuntimeAssignment
        /// The target's frame in its window's global space.
        let frame: CGRect
        /// The scrolling list the target shows in, or nil for fixed chrome.
        let scrollRegionID: UUID?
    }

    // MARK: - Static Variables

    static let shared = BrowserTabSelectionTargets()

    // MARK: - Variables

    private var targets: [UUID: Target] = [:]

    // MARK: - Actions - Lookup

    /// The item of `browser`'s target at `point` in `assignment`'s Space, with
    /// `visibleFrame` giving where each scrolling list shows its rows. A split
    /// covers its members, so the smallest target there wins.
    func item(
        at point: CGPoint, browser: BrowserStore, assignment: BrowserSpaceRuntimeAssignment,
        visibleFrame: (UUID) -> CGRect?
    ) -> BrowserSelectionItemID? {
        targets.values
            .filter { target in
                target.browser === browser && target.assignment == assignment && !target.frame.isEmpty
                    && target.frame.contains(point)
                    && (target.scrollRegionID.map { visibleFrame($0)?.contains(point) ?? false } ?? true)
            }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?
            .itemID
    }

    // MARK: - Mutators

    /// Registers `target` as the one the view `identity` names, or takes that
    /// view's target away when `target` is nil.
    func register(_ target: Target?, for identity: UUID) {
        targets[identity] = target
    }
}
