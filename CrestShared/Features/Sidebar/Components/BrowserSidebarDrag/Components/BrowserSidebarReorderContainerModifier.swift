import SwiftUI

/// Measures and moves a whole reorder item independently of its drag handle.
/// A folder registers this on its full section and arms the lift on its header.
struct BrowserSidebarReorderContainerModifier: ViewModifier {
    let item: BrowserSidebarReorderItem
    let section: BrowserSidebarReorderSection
    let reorder: BrowserSidebarReorderContext
    var parentItemID: BrowserSidebarReorderItemID?
    var isEnabled = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.browserSidebarScrollRegionID) private var scrollRegionID
    @Environment(\.browserSidebarScrollContentSpace) private var scrollContentSpace
    @Environment(\.browserSidebarUsesVirtualRowGeometry) private var usesVirtualRowGeometry
    @Environment(\.browserSidebarWindowDrop) private var windowDrop

    /// Identity for this row's registration. A row that changes section keeps
    /// its item identity but is a different view on either side of the move, and
    /// the departing one leaves after the arriving one has measured itself —
    /// so removal has to name which view is leaving. See
    /// `BrowserSidebarReorderState.RegisteredRow`.
    @State private var identity = UUID()

    private var state: BrowserSidebarReorderState { reorder.state }

    private var isLifted: Bool {
        isEnabled && state.isLifted(item.id)
    }

    private var displacement: CGSize {
        !isEnabled || state.layout.isActive || section.usesGridOrdering ? .zero : state.displacement(for: item.id)
    }

    private var indicator: BrowserSidebarReorderIndicator? {
        !isEnabled || state.layout.isActive || section.usesGridOrdering ? nil : state.indicator(for: item.id)
    }

    private var topSpace: CGFloat { isEnabled ? state.layout.topSpace(for: item.id) : 0 }
    private var bottomSpace: CGFloat { isEnabled ? state.layout.bottomSpace(for: item.id) : 0 }
    private var hidesSource: Bool { isEnabled && state.hidesSource(item.id) }
    private var isRevealing: Bool { isEnabled && state.isRevealing(item.id) }

    func body(content: Content) -> some View {
        let topGap = topSpace
        let bottomGap = bottomSpace
        let measured =
            content
            // Keep the gesture's content alive at its lifted dimensions while
            // its layout slot closes. Removing the view would cancel the drag.
            .frame(
                height: isLifted && state.layout.isActive && !section.usesGridOrdering
                    ? state.frame(ofRow: item.id, in: item.spaceAssignment)?.height : nil,
                alignment: .top
            )
            .modifier(
                BrowserSidebarReorderRowGeometryObserver(
                    item: item,
                    section: section,
                    state: state,
                    parentItemID: parentItemID,
                    isEnabled: isEnabled,
                    isLifted: isLifted,
                    identity: identity,
                    scrollRegionID: scrollRegionID,
                    scrollContentSpace: scrollContentSpace,
                    windowDrop: windowDrop,
                    usesVirtualRowGeometry: usesVirtualRowGeometry
                )
            )
        measured
            .offset(x: displacement.width, y: displacement.height)
            .opacity(hidesSource && !isRevealing ? 0 : 1)
            .animation(nil, value: hidesSource)
            .animation(
                Animation.easeOut(duration: 0.10).unlessReducingMotion(reduceMotion),
                value: isRevealing
            )
            .frame(
                height: isLifted && state.layout.isActive && !section.usesGridOrdering ? 0 : nil, alignment: .top
            )
            .overlay(alignment: indicatorAlignment) {
                if let indicator {
                    BrowserSidebarReorderIndicatorLine(indicator: indicator)
                }
            }
            .padding(.top, topGap)
            .padding(.bottom, bottomGap)
            .overlay(alignment: .top) {
                if topGap > 0 {
                    BrowserSidebarReorderGap(height: topGap)
                }
            }
            .overlay(alignment: .bottom) {
                if bottomGap > 0 {
                    BrowserSidebarReorderGap(height: bottomGap)
                }
            }
            // Layout capacity moves with the gap, across section boundaries.
            .animation(
                CrestMotion.dragSource.unlessReducingMotion(reduceMotion),
                value: ReorderGapAnimationState(
                    topSpace: topGap,
                    bottomSpace: bottomGap,
                    liftedHeight: isLifted ? state.layout.height : 0
                )
            )
            .animation(
                CrestMotion.dragSource.unlessReducingMotion(reduceMotion),
                value: displacement
            )
    }

    private struct ReorderGapAnimationState: Equatable {
        let topSpace: CGFloat
        let bottomSpace: CGFloat
        let liftedHeight: CGFloat
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
        reorder: BrowserSidebarReorderContext,
        parentItemID: BrowserSidebarReorderItemID? = nil,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            BrowserSidebarReorderContainerModifier(
                item: item, section: section, reorder: reorder, parentItemID: parentItemID, isEnabled: isEnabled))
    }
}

private struct BrowserSidebarReorderRowGeometryObserver: ViewModifier {
    let item: BrowserSidebarReorderItem
    let section: BrowserSidebarReorderSection
    let state: BrowserSidebarReorderState
    let parentItemID: BrowserSidebarReorderItemID?
    let isEnabled: Bool
    let isLifted: Bool
    let identity: UUID
    let scrollRegionID: UUID?
    let scrollContentSpace: NamedCoordinateSpace?
    let windowDrop: BrowserSidebarWindowDrop?
    let usesVirtualRowGeometry: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesVirtualRowGeometry {
            content
        } else {
            content
                .onGeometryChange(for: BrowserSidebarReorderRow?.self) { proxy in
                    // Availability participates in the measured value so an
                    // unchanged frame is registered again when its Space returns.
                    guard isEnabled else { return nil }
                    let frame =
                        if let scrollContentSpace {
                            proxy.frame(in: scrollContentSpace)
                        } else {
                            proxy.frame(in: BrowserSidebarReorderSpace.globalSpace)
                        }
                    return BrowserSidebarReorderRow(
                        id: item.id, space: item.spaceAssignment, section: section,
                        frame: frame, parentItemID: parentItemID)
                } action: { row in
                    guard let row else {
                        state.removeRow(item.id, owner: identity)
                        return
                    }
                    // While lifted, this row's reported frame follows the pointer.
                    // Registering it would re-sort the section under the drag and
                    // corrupt the slot indices, so keep the frame it lifted from.
                    guard !isLifted else { return }
                    let globalRow = state.register(
                        row: row,
                        owner: identity,
                        scrollRegionID: scrollRegionID,
                        isContentRelative: scrollContentSpace != nil
                    )
                    windowDrop?.didMeasureRow(globalRow)
                }
                .onChange(of: item.id) { oldID, _ in
                    state.removeRow(oldID, owner: identity)
                }
                .onDisappear {
                    state.removeRow(item.id, owner: identity)
                }
        }
    }
}

extension EnvironmentValues {
    /// True inside a recycled fixed-stride tab run whose container registers
    /// row frames and hit targets once for the run instead of per row.
    @Entry var browserSidebarUsesVirtualRowGeometry = false
}
