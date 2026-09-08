import SwiftUI

/// Registers a region that can accept a lifted sidebar item — an ordered
/// section, a collapsed folder row, or a space picker segment.
///
/// Every zone registered here has a target that is fixed for the life of the
/// view: a section is its placement, a folder row is its folder. The content
/// area is not, so it registers through `BrowserSplitContentDropZoneModifier`
/// instead, which re-registers when the Space it is showing changes.
struct BrowserSidebarReorderZoneModifier: ViewModifier {
    let target: BrowserSidebarReorderZone.Target
    let state: BrowserSidebarReorderState
    /// An inactive zone unregisters itself, so a folder can offer "drop inside"
    /// only while it is collapsed without changing the view's identity.
    var isActive = true
    /// Row-local targets follow the input role without invalidating row content.
    var requiresSelectedSpace = false
    /// Trimmed from the top of the zone. A folder group's nested-folder section
    /// must not claim the group's own header row, or the header stops being a
    /// place to drop *beside* the folder.
    var topInset: CGFloat = 0
    var minimumHeight: CGFloat = 0

    /// Identity for this registration. The mobile space pager keeps neighbouring
    /// pages alive and they register the same targets, so registrations must not
    /// key on the target or offscreen pages clobber the visible one.
    @State private var identity = UUID()
    @Environment(\.browserSidebarScrollRegionID) private var scrollRegionID
    @Environment(\.browserSidebarDropViewportID) private var sidebarViewportID
    @Environment(\.sidebarSpaceIsSelected) private var isSelected

    func body(content: Content) -> some View {
        let isActive =
            self.isActive
            && (!requiresSelectedSpace
                || SidebarSpaceRole.permitsInteraction(isSelected: isSelected, isAvailable: true))
        return
            content
            .onGeometryChange(for: CGRect?.self) { proxy in
                guard isActive else { return nil }
                return proxy.frame(in: BrowserSidebarReorderSpace.globalSpace)
            } action: { frame in
                guard let frame else {
                    state.removeZone(for: identity)
                    return
                }
                state.register(
                    zone: BrowserSidebarReorderZone(
                        target: target,
                        frame: resolvedFrame(frame), minimumHeight: minimumHeight
                    ),
                    for: identity,
                    sidebarViewportID: sidebarViewportID,
                    scrollRegionID: scrollRegionID
                )
            }
            .onDisappear {
                state.removeZone(for: identity)
            }
    }

    /// A nesting target claims only the middle of its row so the edges stay
    /// available for reordering past it.
    private func resolvedFrame(_ frame: CGRect) -> CGRect {
        switch target {
        case .folder, .currentFolder, .currentTab:
            return BrowserSidebarReorderPolicy.nestingFrame(for: frame)
        default: break
        }
        guard topInset > 0, frame.height > topInset else { return frame }
        return CGRect(
            x: frame.minX,
            y: frame.minY + topInset,
            width: frame.width,
            height: frame.height - topInset
        )
    }
}

extension View {
    func browserSidebarReorderZone(
        _ target: BrowserSidebarReorderZone.Target,
        state: BrowserSidebarReorderState,
        isActive: Bool = true,
        requiresSelectedSpace: Bool = false,
        topInset: CGFloat = 0,
        minimumHeight: CGFloat = 0
    ) -> some View {
        modifier(
            BrowserSidebarReorderZoneModifier(
                target: target,
                state: state,
                isActive: isActive,
                requiresSelectedSpace: requiresSelectedSpace,
                topInset: topInset, minimumHeight: minimumHeight
            )
        )
    }
}
