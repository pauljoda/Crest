import SwiftUI

/// Makes a sidebar row draggable in place: it lifts under the pointer, and its
/// neighbours step aside to show where it will land.
///
/// Uses SwiftUI's own `DragGesture` rather than an AppKit dragging session. The
/// AppKit path never rendered a drag image on macOS 27 and its pan recognizer
/// received only a single sample at mouse-up, so there was nothing to animate.
///
/// Ordinary rows also register their container here. Folder headers only arm
/// the gesture: their enclosing section owns measurement and displacement via
/// `BrowserSidebarReorderContainerModifier`.
struct BrowserSidebarReorderSourceModifier: ViewModifier {
    let item: BrowserSidebarReorderItem
    let section: BrowserSidebarReorderSection
    let reorder: BrowserSidebarReorderContext

    var registersContainer = true

    private var state: BrowserSidebarReorderState { reorder.state }

    func body(content: Content) -> some View {
        Group {
            if registersContainer {
                content.browserSidebarReorderContainer(item: item, section: section, reorder: reorder)
            } else {
                content
            }
        }
        .modifier(BrowserSidebarReorderLiftGesture(apply: applyLift))
    }

    /// Feeds a lift's pointer samples into the state. Shared by both platforms so
    /// only the gesture that arms the lift differs.
    private var applyLift: (BrowserSidebarReorderLiftPhase) -> Void {
        { phase in
            switch phase {
            case .moved(let startLocation, let location):
                if state.isLifted(item.id) {
                    state.update(pointer: location)
                } else if !state.isDragging {
                    state.begin(item: item, section: section, at: startLocation)
                    state.update(pointer: location)
                }
            case .released:
                guard state.isLifted(item.id) else { return }
                // Replace the temporary gap with its real row in one layout
                // transaction. The floating preview owns the visible landing.
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    guard let drop = state.end(retainingPreview: BrowserSidebarReorderPolicy.drawsOwnLift) else {
                        return
                    }
                    reorder.commit(drop.target, for: drop.item)
                }
            }
        }
    }
}

extension View {
    func browserSidebarReorderSource(
        item: BrowserSidebarReorderItem,
        section: BrowserSidebarReorderSection,
        reorder: BrowserSidebarReorderContext,
        registersContainer: Bool = true
    ) -> some View {
        modifier(
            BrowserSidebarReorderSourceModifier(
                item: item,
                section: section,
                reorder: reorder,
                registersContainer: registersContainer
            )
        )
    }
}
