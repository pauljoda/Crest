import SwiftUI

/// Makes a sidebar row draggable in place: it lifts under the pointer, and its
/// neighbours step aside to show where it will land.
///
/// Uses SwiftUI's own `DragGesture` rather than an AppKit dragging session. The
/// AppKit path never rendered a drag image on macOS 27 and its pan recognizer
/// received only a single sample at mouse-up, so there was nothing to animate.
///
/// What this modifier owns is the row's structure during a drag: the gap the
/// lifted row leaves behind, the neighbours sliding into and out of it, and the
/// insertion line. What it deliberately does not own is the preview that chases
/// the pointer. That is drawn above the window — see
/// `BrowserSidebarReorderState.floatingLift` — because a preview drawn here is
/// clipped by everything it travels over.
struct BrowserSidebarReorderSourceModifier: ViewModifier {
    let item: BrowserSidebarReorderItem
    let section: BrowserSidebarReorderSection
    let reorder: BrowserSidebarReorderContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Identity for this row's registration. A row that changes section keeps
    /// its item identity but is a different view on either side of the move, and
    /// the departing one leaves after the arriving one has measured itself —
    /// so removal has to name which view is leaving. See
    /// `BrowserSidebarReorderState.RegisteredRow`.
    @State private var identity = UUID()

    private var state: BrowserSidebarReorderState { reorder.state }

    private var isLifted: Bool {
        state.isLifted(item.id)
    }

    private var displacement: CGSize {
        state.displacement(for: item.id)
    }

    private var indicator: BrowserSidebarReorderIndicator? {
        state.indicator(for: item.id)
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: BrowserSidebarReorderSpace.globalSpace)
            } action: { frame in
                // While lifted, this row's reported frame follows the pointer.
                // Registering it would re-sort the section under the drag and
                // corrupt the slot indices, so keep the frame it lifted from.
                guard !isLifted else { return }
                state.register(
                    row: BrowserSidebarReorderRow(
                        id: item.id,
                        section: section,
                        frame: frame
                    ),
                    owner: identity
                )
            }
            .onDisappear {
                state.removeRow(item.id, owner: identity)
            }
            // A lifted row does not move: `displacement` is zero for the row
            // being dragged, and the travelling copy of it is drawn elsewhere.
            .offset(x: displacement.width, y: displacement.height)
            // The row itself is never the thing under the pointer. macOS draws
            // the lift in a window-level host so it cannot be clipped, and iOS
            // lifts through drag-and-drop, which draws its own preview under the
            // finger. Either way the row stands down and keeps only its slot —
            // the gap the drop is about to close.
            .opacity(isLifted ? 0 : 1)
            .overlay(alignment: indicatorAlignment) {
                if let indicator {
                    BrowserSidebarReorderIndicatorLine(indicator: indicator)
                }
            }
            // Neighbours settle into the gap rather than snapping into it.
            .animation(
                BrowserVisualAccessibilityPolicy.animation(
                    CrestMotion.dragSource,
                    reduceMotion: reduceMotion
                ),
                value: displacement
            )
            // Simultaneous, not exclusive: rows are buttons, and their own
            // gesture wins an exclusive contest, which suppresses the lift.
            .modifier(BrowserSidebarReorderLiftGesture(apply: applyLift))
    }

    private var indicatorAlignment: Alignment {
        guard let indicator else { return .top }
        switch (indicator.flowsHorizontally, indicator.side) {
        case (true, .before): return .leading
        case (true, .after): return .trailing
        case (false, .before): return .top
        case (false, .after): return .bottom
        }
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
                guard state.isLifted(item.id), let drop = state.end() else { return }
                reorder.commit(drop.target, for: drop.item)
            }
        }
    }
}

extension View {
    func browserSidebarReorderSource(
        item: BrowserSidebarReorderItem,
        section: BrowserSidebarReorderSection,
        reorder: BrowserSidebarReorderContext
    ) -> some View {
        modifier(
            BrowserSidebarReorderSourceModifier(
                item: item,
                section: section,
                reorder: reorder
            )
        )
    }
}
