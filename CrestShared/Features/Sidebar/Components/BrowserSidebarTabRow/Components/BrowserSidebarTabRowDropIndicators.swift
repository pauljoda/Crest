import SwiftUI

/// The insertion lines a row draws while a tab is being dragged over the list.
///
/// Only shells that put the feedback on the rows themselves apply these; where
/// the section's own zone carries the whole answer, an individual row stays
/// quiet and this modifier steps aside entirely.
struct BrowserSidebarTabRowDropIndicators: ViewModifier {
    let configuration: BrowserSidebarTabRowConfiguration
    let isDropTargeted: Bool
    @Binding var dropTargetHeight: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if configuration.capabilities.showsRowDropIndicators {
            content
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    dropTargetHeight = newHeight
                }
                .overlay(alignment: .top) {
                    BrowserTabDropIndicator(
                        location: configuration.beforeDropLocation,
                        dragState: configuration.browser.tabDragState,
                        isTargeted: isDropTargeted
                    )
                }
                .overlay(alignment: .bottom) { trailingIndicator }
        } else {
            content
        }
    }

    /// The last row in a run owns the line below it: no row follows to draw
    /// the same seam from its own top edge.
    @ViewBuilder
    private var trailingIndicator: some View {
        if BrowserTabRowIndicatorOwnershipPolicy.showsAfterRowIndicator(
            hasVisibleFollowingRow: configuration.hasVisibleFollowingRow
        ) {
            BrowserTabDropIndicator(
                location: configuration.afterDropLocation,
                dragState: configuration.browser.tabDragState,
                isTargeted: isDropTargeted
            )
        }
    }
}
