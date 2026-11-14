import SwiftUI

/// The rows of one list the core publishes, on every shell: the top level of
/// a section or the inside of a folder.
///
/// It reads only that list and the objects its rows stand for, and hands each
/// row its objects, so a move redraws only the list it moves within, a new
/// title or icon redraws only its own row, and showing another tab redraws no
/// list.
///
/// Tab rows are made only as they scroll into view, in runs between the
/// folders and splits, which are made with the list. A lazy stack places the
/// rows it has not made yet from the ones it has, and tab rows share one
/// height, so those places are right and the list settles in one pass. A
/// folder is as tall as everything open inside it, and a split as its members:
/// in a lazy stack, each one it made moved the rows it had not, which moved
/// what was on screen and what it had to make next, and the sidebar could lay
/// itself out again and again without ever settling.
struct BrowserSidebarListRows<Trailing: View>: View {
    // MARK: - Types

    /// A stretch of the list laid out one way: the tab rows between two
    /// folders or splits, made as they scroll into view, or one folder or
    /// split, made with the list.
    struct Run: Identifiable {
        enum ID: Hashable {
            /// The tab rows after the item, or at the top of the list. A run
            /// keeps its identity while tabs come and go at its top.
            case tabs(after: BrowserSidebarReorderItemID?)
            case item(BrowserSidebarReorderItemID)
        }

        let id: ID
        var items: [BrowserSidebarListItem]

        var isLazy: Bool {
            if case .tabs = id { true } else { false }
        }

        /// The list's items as runs, in order.
        static func runs(of items: [BrowserSidebarListItem]) -> [Run] {
            var runs: [Run] = []
            for item in items {
                guard item.isTabRow else {
                    runs.append(Run(id: .item(item.id), items: [item]))
                    continue
                }
                if let last = runs.indices.last, runs[last].isLazy {
                    runs[last].items.append(item)
                } else {
                    runs.append(Run(id: .tabs(after: runs.last?.items.last?.id), items: [item]))
                }
            }
            return runs
        }
    }

    // MARK: - Variables

    let list: SidebarListModel
    let context: BrowserSidebarListContext
    /// The tabs a collapsed folder around the list keeps on screen, which
    /// shows only the rows that hold one, or nil for every row.
    var keptTabIDs: Set<UUID>? = nil
    /// What the list shows after its rows, given the rows it holds, such as
    /// the band an empty run keeps.
    @ViewBuilder var trailing: ([BrowserSidebarListItem]) -> Trailing

    var body: some View {
        let items = BrowserSidebarListItem.items(of: list, in: context.space).filter(isShown)
        VStack(spacing: 0) {
            ForEach(Run.runs(of: items)) { run in
                if run.isLazy {
                    LazyVStack(spacing: 0) { rows(run.items) }
                } else {
                    rows(run.items)
                }
            }
            trailing(items)
        }
        .crestCollectionMotion(ids: items.map(\.collectionMotionID))
    }

    // MARK: - Actions - Rows

    private func rows(_ items: [BrowserSidebarListItem]) -> some View {
        ForEach(items) { item in
            BrowserSidebarListRow(item: item, context: context, keptTabIDs: keptTabIDs).equatable()
        }
    }

    /// Whether `item` shows: every row of an open list, and of a kept one
    /// the rows that hold a kept tab, the tab itself, its split, or a folder
    /// on the way to it.
    private func isShown(_ item: BrowserSidebarListItem) -> Bool {
        guard let keptTabIDs else { return true }
        return keptTabIDs.contains { item.content.contains(tabID: $0, in: context.space) }
    }
}

extension BrowserSidebarListRows: @MainActor Equatable {
    /// Rows views are equal when they draw the same list for the same Space and
    /// window, as SwiftUI compares a view's inputs, so a section that redraws
    /// leaves its list alone. What trails the rows depends only on those.
    static func == (lhs: BrowserSidebarListRows, rhs: BrowserSidebarListRows) -> Bool {
        lhs.list === rhs.list && lhs.context == rhs.context && lhs.keptTabIDs == rhs.keptTabIDs
    }
}

extension BrowserSidebarListRows where Trailing == EmptyView {
    init(list: SidebarListModel, context: BrowserSidebarListContext, keptTabIDs: Set<UUID>? = nil) {
        self.init(list: list, context: context, keptTabIDs: keptTabIDs) { _ in EmptyView() }
    }
}

/// One row of a sidebar list: a tab, a split, or a folder with what it holds,
/// indented to the folders around it.
struct BrowserSidebarListRow: View {
    // MARK: - Variables

    let item: BrowserSidebarListItem
    let context: BrowserSidebarListContext
    /// The tabs a collapsed folder around the row keeps on screen, which a
    /// folder row shows the way to in place of its contents.
    var keptTabIDs: Set<UUID>? = nil

    var body: some View {
        content.environment(\.sidebarLayerDepth, item.depth)
    }

    @ViewBuilder
    private var content: some View {
        switch item.content {
        case .tab(let tab):
            BrowserSidebarTabRow(tab: tab, context: context)
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
            BrowserSidebarSplitGroupRow(groupID: groupID, members: members, context: context)
                .equatable()
                .modifier(BrowserSidebarFolderRowIndent(depth: item.depth))
                #if os(macOS)
                    .geometryGroup()
                #endif
        case .folder(let folder):
            BrowserFolderGroup(folder: folder, depth: item.depth, context: context, inheritedKeptTabIDs: keptTabIDs)
                .equatable()
                .padding(.trailing, item.depth > 0 ? BrowserFolderLayout.nestingIndent : 0)
                .modifier(
                    BrowserFolderOffscreenPlaceholder(folder: folder, context: context, isEnabled: keptTabIDs == nil)
                )
                .crestCollectionItemTransition()
        }
    }
}

extension BrowserSidebarListRow: @MainActor Equatable {
    /// Rows are equal when they stand for the same objects in the same place,
    /// as SwiftUI compares a view's inputs, so a list that redraws leaves every
    /// unchanged row alone.
    static func == (lhs: BrowserSidebarListRow, rhs: BrowserSidebarListRow) -> Bool {
        lhs.item == rhs.item && lhs.context == rhs.context && lhs.keptTabIDs == rhs.keptTabIDs
    }
}

/// Steps a row inside a folder in by the folders around it: its surface by
/// the folders' padding, and its icon and title past the folder's own. A row
/// at a section's top level stays put. Rows inside a folder stack as they do
/// at the top level; the folder's padding is what holds them off its edges.
private struct BrowserSidebarFolderRowIndent: ViewModifier {
    let depth: Int

    @Environment(\.sidebarFolderRowTransition) private var transition

    @ViewBuilder
    func body(content: Content) -> some View {
        if depth > 0 {
            content
                .environment(\.sidebarRowContentIndent, BrowserFolderLayout.rowContentIndent(depth: depth))
                .padding(.leading, BrowserFolderLayout.rowLeadingInset(depth: depth - 1))
                .padding(.trailing, BrowserFolderLayout.nestingIndent)
                .frame(maxWidth: .infinity)
                // The innermost transition is the one a row uses, so a row
                // that comes and goes its own way says so here.
                .transition(transition ?? .opacity.combined(with: .move(edge: .top)))
        } else {
            content
        }
    }
}
