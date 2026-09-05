import SwiftUI

/// Places a small bounded grid without destroying the source of an active drag.
struct BrowserPinnedTabSlotLayout: Layout {
    let projection: BrowserPinnedTabReorderLayout

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? BrowserChromeLayout.sidebarIdealWidth, height: projection.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let resting = BrowserPinnedTabReorderLayout(ids: projection.ids)
        for (index, subview) in subviews.enumerated() {
            let slot: BrowserPinnedTabReorderLayout.Slot =
                index < projection.ids.count ? .tab(projection.ids[index]) : .gap
            // The invisible source retains a frame and its recognizer even when
            // it has left the grid. It contributes no capacity to this layout.
            let frame =
                projection.frame(for: slot, in: bounds) ?? resting.frame(for: slot, in: bounds)
                ?? CGRect(origin: bounds.origin, size: .zero)
            subview.place(at: frame.origin, anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}
