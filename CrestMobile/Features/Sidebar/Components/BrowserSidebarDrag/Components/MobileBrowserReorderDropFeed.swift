import SwiftUI

/// Feeds the reorder state the pointer samples a system drag reports, from one
/// region of the touch shell.
///
/// A touch lift takes its positions from the drop side — there is no gesture
/// streaming them, because `UIContextMenuInteraction` cancels anything that
/// competes with a row's menu — so every region a finger may carry a lift over
/// has to offer one of these. Two do: the sidebar, and the content area beside
/// it through `MobileSplitContentDropFeed`.
///
/// Attached to a whole region rather than to the runs inside it. On the sidebar
/// that is what reaches the pinned grid, which sits outside the scrolling list;
/// a feed attached to the list alone never sees the pointer over pinned, and a
/// tab could not be dropped there. The reorder state resolves everything from a
/// single global point regardless, so all this has to do is convert the drop's
/// local location using the region's own origin.
struct MobileBrowserReorderDropFeed: ViewModifier {
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
