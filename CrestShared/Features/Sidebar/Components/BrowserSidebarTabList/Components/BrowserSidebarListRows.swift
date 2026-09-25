import SwiftUI

/// The rows of one list the core publishes, on every shell: the top level of
/// a section or the inside of a folder, in a lazy stack.
///
/// It reads only that list and the objects its rows stand for, and hands each
/// row its objects, so a move redraws only the list it moves within, a new
/// title or icon redraws only its own row, and showing another tab redraws no
/// list. Rows are made only as they scroll into view, so a folder that opens
/// or a section that grows lays out what is on screen and nothing more.
struct BrowserSidebarListRows<Trailing: View>: View {
    // MARK: - Variables

    let list: SidebarListModel
    let context: BrowserSidebarListContext
    /// What the list shows after its rows, given the rows it holds, such as
    /// the band an empty run draws its insertion line in.
    @ViewBuilder var trailing: ([BrowserSidebarListItem]) -> Trailing

    var body: some View {
        let items = BrowserSidebarListItem.items(
            of: list, in: context.space, namesFollowingTabs: context.capabilities.showsRowDropIndicators)
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                BrowserSidebarListRow(item: item, context: context).equatable()
            }
            trailing(items)
        }
        .crestCollectionMotion(ids: items.map(\.collectionMotionID))
    }
}

extension BrowserSidebarListRows: Equatable {
    /// Rows views are equal when they draw the same list for the same Space and
    /// window, as SwiftUI compares a view's inputs, so a section that redraws
    /// leaves its list alone. What trails the rows depends only on those.
    nonisolated static func == (lhs: BrowserSidebarListRows, rhs: BrowserSidebarListRows) -> Bool {
        lhs.list === rhs.list && lhs.context == rhs.context
    }
}

extension BrowserSidebarListRows where Trailing == EmptyView {
    init(list: SidebarListModel, context: BrowserSidebarListContext) {
        self.init(list: list, context: context) { _ in EmptyView() }
    }
}

/// One row of a sidebar list: a tab, a split, or a folder with what it holds,
/// indented to the folders around it.
struct BrowserSidebarListRow: View {
    // MARK: - Variables

    let item: BrowserSidebarListItem
    let context: BrowserSidebarListContext

    var body: some View {
        switch item.content {
        case .tab(let tab):
            BrowserSidebarTabRow(tab: tab, context: context, followingTabID: item.followingTabID)
                .equatable()
                .modifier(BrowserSidebarFolderRowIndent(depth: item.depth))
                #if os(macOS)
                    // Resolve collection movement once for the whole row,
                    // including native controls and SwiftUI drawing layers.
                    .geometryGroup()
                #endif
                // Keep the identity used when revealing the shown tab.
                .id(tab.id)
        case .split(let groupID, let members):
            BrowserSidebarSplitGroupRow(
                groupID: groupID, members: members, context: context, followingTabID: item.followingTabID
            )
            .equatable()
            .modifier(BrowserSidebarFolderRowIndent(depth: item.depth))
            #if os(macOS)
                .geometryGroup()
            #endif
        case .folder(let folder):
            BrowserFolderGroup(folder: folder, depth: item.depth, context: context)
                .equatable()
                .padding(.trailing, item.depth > 0 ? BrowserFolderLayout.contentsInset : 0)
                .crestCollectionItemTransition()
        }
    }
}

extension BrowserSidebarListRow: Equatable {
    /// Rows are equal when they stand for the same objects in the same place,
    /// as SwiftUI compares a view's inputs, so a list that redraws leaves every
    /// unchanged row alone.
    nonisolated static func == (lhs: BrowserSidebarListRow, rhs: BrowserSidebarListRow) -> Bool {
        lhs.item == rhs.item && lhs.context == rhs.context
    }
}

/// Steps a row inside a folder in by the folders around it, the rhythm the
/// folder's own header keeps. A row at a section's top level stays put.
private struct BrowserSidebarFolderRowIndent: ViewModifier {
    let depth: Int

    @ViewBuilder
    func body(content: Content) -> some View {
        if depth > 0 {
            content
                .padding(.leading, BrowserFolderLayout.rowLeadingInset(depth: depth - 1))
                .padding(.trailing, BrowserFolderLayout.contentsInset)
                .padding(.vertical, BrowserFolderAppearancePolicy.regionInset)
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            content
        }
    }
}
