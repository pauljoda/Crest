import Foundation

/// A tab the window just opened, which its sidebar brings into view once.
/// Each request is new, so opening the same tab again asks again.
struct BrowserSidebarRevealRequest: Equatable {
    // MARK: - Variables

    let id = UUID()
    let tabID: UUID
    let spaceID: UUID

    // MARK: - Actions - Revealing

    /// What `space`'s scrolling list reveals for the tab, or nil when the
    /// request is for another Space or the list cannot show it: the row of
    /// the tab, or of the outermost collapsed folder around it, with where it
    /// falls among the rows the list draws. A pinned tab sits in the grid
    /// above the list, and a tab in a collapsed section is reached through
    /// its header, which never scrolls away.
    @MainActor func reveal(in space: SpaceModel) -> SidebarScrollReveal? {
        guard spaceID == space.id, let tab = space.tabs.model(tabID), !tab.placement.isGrid,
            !tab.placement.isCollapsible || space.settings.isSavedTabsExpanded
        else { return nil }
        var rowID = tabID
        var folderID = tab.folderID
        var visited: Set<UUID> = []
        while let id = folderID, visited.insert(id).inserted, let folder = space.folders.model(id) {
            if folder.isCollapsed { rowID = id }
            folderID = folder.parentID
        }
        let rows = Self.drawnRows(in: space)
        let index = rows.firstIndex { $0.id == rowID || $0.members.contains(rowID) }
        return SidebarScrollReveal(
            requestID: id, rowID: rowID,
            placement: index.map { SidebarScrollReveal.Placement(index: $0, count: rows.count) })
    }

    /// The rows the list draws, in order: the saved section while it is
    /// open, then the current one, each with the insides of its open folders.
    @MainActor private static func drawnRows(in space: SpaceModel) -> [SidebarRow] {
        var rows: [SidebarRow] = []
        func visit(_ list: SidebarListModel) {
            for row in list.rows {
                rows.append(row)
                if row.kind.opensList, space.folders.model(row.id)?.isCollapsed == false {
                    visit(space.sidebar.inside(row.id))
                }
            }
        }
        if space.settings.isSavedTabsExpanded { visit(space.sidebar.section(.saved)) }
        visit(space.sidebar.section(.current))
        return rows
    }
}
