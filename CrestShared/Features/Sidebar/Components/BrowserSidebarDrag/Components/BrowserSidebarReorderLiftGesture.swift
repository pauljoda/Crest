import SwiftUI

/// A pointer sample from whichever source armed the lift.
enum BrowserSidebarReorderLiftPhase {
    case moved(startLocation: CGPoint, location: CGPoint)
    case released
}

/// Arms a reorder lift from pointer movement.
///
/// macOS only. Content is not dragged to scroll there, so a `DragGesture` is
/// unambiguous, and it recognises simultaneously because a row is a button that
/// would otherwise win the contest outright.
///
/// iOS cannot use a gesture at all: a row carries a context menu, and
/// `UIContextMenuInteraction` cancels any competing gesture the moment it claims
/// the touch — no press duration can win that. Drag-and-drop is the one path the
/// system arbitrates against a context menu, so iOS lifts from `.onDrag` and
/// takes its positions from a drop delegate instead.
struct BrowserSidebarReorderLiftGesture: ViewModifier {
    let apply: (BrowserSidebarReorderLiftPhase) -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
            content.simultaneousGesture(pointerDrag)
        #else
            content
        #endif
    }

    #if os(macOS)
        private var pointerDrag: some Gesture {
            DragGesture(
                minimumDistance: BrowserSidebarReorderPolicy.liftDistance,
                coordinateSpace: BrowserSidebarReorderSpace.coordinateSpace
            )
            .onChanged { value in
                apply(
                    .moved(
                        startLocation: value.startLocation,
                        location: value.location
                    )
                )
            }
            .onEnded { _ in apply(.released) }
        }
    #endif
}
