import CoreGraphics
import Foundation

/// A lift that has to be drawn by something other than the view tree it came
/// from, together with everything that drawing needs.
///
/// Every promoted lift is one. A lift drawn in the view tree is at the mercy of
/// whatever it happens to be over: the page is a `WKWebView`, an `NSView`
/// subtree inside the same hosting view, and AppKit composites view subtrees
/// above everything SwiftUI draws beside them no matter what `zIndex` they are
/// given — but window chrome, insets, and the bands a view transition passes
/// through clip a travelling preview just as effectively. Handing the preview
/// over part-way through a drag only moves the seam. So the whole pointer-
/// chasing visual, for the whole lift, belongs to a host that paints above the
/// window: see the macOS drag preview window host. What stays in the sidebar is
/// the structure — the gap the lifted row leaves, the neighbours stepping aside,
/// the drop indicator.
///
/// The value is derived from the live drag and nothing else: the state that
/// produced it is still the only source of truth, and a host that renders this
/// is a presentation of that state rather than a second copy of it.
struct BrowserSidebarFloatingLift: Equatable, Sendable {
    /// What is being lifted, so the host can resolve its real row content — a
    /// tab, a folder, or a whole split group.
    let item: BrowserSidebarReorderItem
    /// What the drop would make of it, and how far the morph has gone. Only a
    /// tab ever changes shape; a folder and a group stay rows wherever they go.
    let shape: BrowserTabDragPreviewShape
    let progress: CGFloat
    /// The pointer, in the global space frames are registered in.
    let pointer: CGPoint
    /// Where inside the row the pointer grabbed it.
    let grabOffset: CGSize
    /// The width the row form of the preview is drawn at.
    let rowWidth: CGFloat

    /// The Space profile the preview resolves favicons against.
    var profileID: UUID {
        item.spaceAssignment.profileID
    }

    /// The lifted tab, when a tab is what was lifted.
    var tabID: TabID? {
        item.id.tabID
    }

    /// Top-left of the preview, in the same global space as `pointer`.
    var origin: CGPoint {
        BrowserTabDragPreviewLayout.pointerAnchoredOrigin(
            pointer: pointer,
            grabOffset: grabOffset,
            targetShape: shape,
            progress: progress,
            rowWidth: rowWidth
        )
    }
}
