import SwiftUI

/// Registers the live bounds of a sidebar row, tile or folder header for
/// selection clicks, without intercepting input. See
/// `BrowserTabSelectionTargets`.
struct BrowserPlatformTabSelectionTarget: ViewModifier {
    let itemID: BrowserSelectionItemID?
    let browser: BrowserStore?
    let assignment: BrowserSpaceRuntimeAssignment
    let isEnabled: Bool

    @Environment(\.browserSidebarScrollRegionID) private var scrollRegionID
    /// Identity for this view's registration, so a row the sidebar builds
    /// again never takes away the target of the one that replaced it.
    @State private var identity = UUID()

    func body(content: Content) -> some View {
        let itemID = isEnabled && browser != nil ? itemID : nil
        content
            .onGeometryChange(for: CGRect?.self) { proxy in
                itemID == nil ? nil : proxy.frame(in: .global)
            } action: { frame in
                BrowserTabSelectionTargets.shared.register(
                    frame.flatMap { frame in
                        itemID.map {
                            BrowserTabSelectionTargets.Target(
                                itemID: $0, browser: browser, assignment: assignment, frame: frame,
                                scrollRegionID: scrollRegionID)
                        }
                    },
                    for: identity)
            }
            .onDisappear { BrowserTabSelectionTargets.shared.register(nil, for: identity) }
    }
}
