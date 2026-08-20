import SwiftUI

/// The Space strip every sidebar is built around, and the one thing to show
/// when there are no Spaces to strip.
///
/// Both shells wire the pager the same way — the same Spaces, the same
/// selection, the same lock while a drag is in flight — and differ only in the
/// page they draw inside it and the chrome they wrap around it. So the wiring
/// lives here and the page arrives as a builder.
struct BrowserSidebarSpacePager<Page: View>: View {
    let context: BrowserSidebarContext
    @ViewBuilder let page: (BrowserSpace, Bool) -> Page

    var body: some View {
        if context.availableSpaces.isEmpty {
            ContentUnavailableView("No Spaces", systemImage: "square.grid.2x2")
        } else {
            BrowserSpacePager(
                spaces: context.availableSpaces,
                selectedSpaceID: context.browser.session.selectedSpaceID,
                isInteractionLocked: isInteractionLocked,
                selectSpace: context.selectSpace,
                settledSpace: context.settleSpaceSelection,
                content: page
            )
        }
    }

    /// A drag in flight owns the horizontal axis: paging under it would move
    /// the rows the drop is aimed at.
    private var isInteractionLocked: Bool {
        context.browser.tabDragState.item != nil
            || context.browser.folderDragState.item != nil
    }
}
