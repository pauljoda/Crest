import SwiftUI

/// Registers live bounds for sidebar selection without creating per-row AppKit
/// views or intercepting input. Inside a scrolling list, frames are measured
/// in content space so scrolling fires zero per-row geometry callbacks.
struct BrowserPlatformTabSelectionTarget: ViewModifier {
    let itemID: BrowserSelectionItemID?
    let browser: BrowserStore?
    let assignment: BrowserSpaceRuntimeAssignment
    let isEnabled: Bool

    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction: BrowserSidebarInteractionState?
    @Environment(\.browserSidebarScrollRegionID) private var scrollRegionID
    @Environment(\.browserSidebarScrollContentSpace) private var scrollContentSpace
    @Environment(\.browserSidebarDropViewportID) private var sidebarViewportID
    @State private var identity = UUID()

    func body(content: Content) -> some View {
        let itemID = isEnabled ? itemID : nil
        let contentSpace = scrollContentSpace
        let state = sidebarInteraction?.sidebarReorderState
        content
            .onGeometryChange(for: CGRect?.self) { proxy in
                guard itemID != nil, state != nil else { return nil }
                if let contentSpace {
                    return proxy.frame(in: contentSpace)
                }
                return proxy.frame(in: BrowserSidebarReorderSpace.globalSpace)
            } action: { frame in
                guard let state else { return }
                guard let itemID, let frame, !frame.isEmpty else {
                    state.removeSelectionTarget(for: identity)
                    return
                }
                state.register(
                    selectionTarget: itemID,
                    in: assignment,
                    frame: frame,
                    for: identity,
                    sidebarViewportID: sidebarViewportID,
                    scrollRegionID: scrollRegionID,
                    isContentRelative: contentSpace != nil
                )
            }
            .onDisappear {
                state?.removeSelectionTarget(for: identity)
            }
    }
}
