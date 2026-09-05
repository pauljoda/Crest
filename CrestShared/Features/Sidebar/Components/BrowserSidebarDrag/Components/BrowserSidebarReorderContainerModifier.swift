import SwiftUI

/// Measures and moves a whole reorder item independently of its drag handle.
/// A folder registers this on its full section and arms the lift on its header.
struct BrowserSidebarReorderContainerModifier: ViewModifier {
    let item: BrowserSidebarReorderItem
    let section: BrowserSidebarReorderSection
    let reorder: BrowserSidebarReorderContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.browserSidebarScrollRegionID) private var scrollRegionID

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
        state.layout.isActive || section.usesGridOrdering ? .zero : state.displacement(for: item.id)
    }

    private var indicator: BrowserSidebarReorderIndicator? {
        state.layout.isActive || section.usesGridOrdering ? nil : state.indicator(for: item.id)
    }

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            BrowserSidebarReorderGap(height: state.layout.topSpace(for: item.id))
            content
                // Keep the gesture's content alive at its lifted dimensions while
                // its layout slot closes. Removing the view would cancel the drag.
                .frame(
                    height: isLifted && state.layout.isActive && !section.usesGridOrdering ? state.layout.height : nil,
                    alignment: .top
                )
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
                            space: item.spaceAssignment,
                            section: section,
                            frame: frame
                        ),
                        owner: identity,
                        scrollRegionID: scrollRegionID
                    )
                }
                .onDisappear {
                    state.removeRow(item.id, owner: identity)
                }
                .offset(x: displacement.width, y: displacement.height)
                .opacity(state.hidesSource(item.id) && !state.isRevealing(item.id) ? 0 : 1)
                .animation(nil, value: state.hidesSource(item.id))
                .animation(
                    BrowserVisualAccessibilityPolicy.animation(.easeOut(duration: 0.10), reduceMotion: reduceMotion),
                    value: state.isRevealing(item.id)
                )
                .frame(
                    height: isLifted && state.layout.isActive && !section.usesGridOrdering ? 0 : nil, alignment: .top
                )
                .overlay(alignment: indicatorAlignment) {
                    if let indicator {
                        BrowserSidebarReorderIndicatorLine(indicator: indicator)
                    }
                }
            BrowserSidebarReorderGap(height: state.layout.bottomSpace(for: item.id))
        }
        // Layout capacity moves with the gap, across section boundaries.
        .animation(
            BrowserVisualAccessibilityPolicy.animation(CrestMotion.dragSource, reduceMotion: reduceMotion),
            value: [
                state.layout.topSpace(for: item.id), state.layout.bottomSpace(for: item.id),
                isLifted ? state.layout.height : 0,
            ]
        )
        .animation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.dragSource,
                reduceMotion: reduceMotion
            ),
            value: displacement
        )
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

}

extension View {
    func browserSidebarReorderContainer(
        item: BrowserSidebarReorderItem,
        section: BrowserSidebarReorderSection,
        reorder: BrowserSidebarReorderContext
    ) -> some View {
        modifier(BrowserSidebarReorderContainerModifier(item: item, section: section, reorder: reorder))
    }
}
