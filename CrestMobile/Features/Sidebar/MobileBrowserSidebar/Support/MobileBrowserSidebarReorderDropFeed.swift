import SwiftUI

/// Feeds the compact sidebar's reorder state the pointer samples a system drag
/// reports.
///
/// Attached to the whole sidebar — pinned strip included — because the pinned
/// grid sits outside the scrolling list. A feed attached to the list alone never
/// sees the pointer over pinned, so a tab could not be dropped there.
struct MobileBrowserSidebarReorderDropFeed: ViewModifier {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    /// Where the fed region sits, so the delegate can report positions in the
    /// same global space the zones measured themselves in.
    @State private var origin = CGPoint.zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: BrowserSidebarReorderSpace.globalSpace)
            } action: { frame in
                origin = frame.origin
            }
            .onDrop(
                of: [.json],
                delegate: BrowserSidebarReorderDropDelegate(
                    reorder: BrowserSidebarReorderContext(
                        browser: browser,
                        spaceAccess: spaceAccess
                    ),
                    origin: origin
                )
            )
    }
}
