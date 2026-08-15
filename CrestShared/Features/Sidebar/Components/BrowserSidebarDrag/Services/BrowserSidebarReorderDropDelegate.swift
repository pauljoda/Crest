import SwiftUI

/// Feeds an in-flight `.onDrag` session's position into the reorder state.
///
/// iOS lifts through drag-and-drop rather than a gesture, so the pointer has to
/// come from the drop side. One delegate covering the whole sidebar is enough:
/// the reorder state resolves everything from a single global point, so this only
/// has to convert the drop's local location using the area's own origin.
struct BrowserSidebarReorderDropDelegate: DropDelegate {
    let reorder: BrowserSidebarReorderContext
    /// Global origin of the view this delegate is attached to.
    let origin: CGPoint

    func dropEntered(info: DropInfo) {
        track(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        track(info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        track(info)
        guard let drop = reorder.state.end() else { return false }
        reorder.commit(drop.target, for: drop.item)
        return true
    }

    private func track(_ info: DropInfo) {
        // No isDragging guard: the first tracked position is what PROMOTES a
        // staged lift into a real one — `update` stages through or ignores the
        // sample itself, and gating on an already-live lift here would deadlock
        // the promotion and leave drops resolving nowhere.
        reorder.state.update(
            pointer: CGPoint(
                x: origin.x + info.location.x,
                y: origin.y + info.location.y
            )
        )
    }
}
