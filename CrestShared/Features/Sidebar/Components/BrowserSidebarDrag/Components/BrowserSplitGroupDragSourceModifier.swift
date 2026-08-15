import SwiftUI

/// Makes a stacked split-group row draggable as one block.
///
/// Deliberately thinner than `BrowserTabDragSourceModifier`: a group has no
/// pinned form to morph into, so it needs the in-view reorder source and
/// whatever its platform uses to arm a lift, and nothing else. Member lines
/// never carry a source of their own — tearing one out mid-drag would break the
/// run's contiguity and dissolve the split under the pointer.
struct BrowserSplitGroupDragSourceModifier: ViewModifier {
    let item: BrowserSplitGroupDragItem
    /// The run this row stands for. Only the platform that draws its own lift
    /// preview reads it; the identities the commit needs travel in `item`.
    var members: [BrowserTab] = []
    let placement: TabPlacement
    let folderID: FolderID?
    var reorder: BrowserSidebarReorderContext?
    var isEnabled = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled, let reorder {
            content
                .modifier(
                    BrowserPlatformSplitGroupDragSourceModifier(
                        item: item,
                        members: members,
                        placement: placement,
                        folderID: folderID,
                        reorder: reorder
                    )
                )
        } else {
            // No reorder context: previews and fixtures render a static row.
            content
        }
    }
}
