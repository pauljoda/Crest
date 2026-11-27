import Foundation

/// A tab the window just opened, which the list of its Space brings into view
/// once. Each request is new, so opening the same tab again asks again.
struct BrowserSidebarRevealRequest: Equatable {
    // MARK: - Static Variables

    /// How long a request waits for its list. One a list takes later, as when
    /// the person comes back to the Space, is stale and reveals nothing.
    private static let lifetime: Duration = .seconds(1)

    // MARK: - Variables

    let id = UUID()
    let tabID: UUID
    let spaceID: UUID
    private let madeAt = ContinuousClock.now

    var isStale: Bool { ContinuousClock.now - madeAt > Self.lifetime }

    // MARK: - Actions - Revealing

    /// Where `space`'s list finds the tab's row now, read from the frames the
    /// list's rows registered for reordering in `scrollRegionID`; nil when
    /// the list has nothing to reveal. A pinned tab sits in the grid above
    /// the list, and a tab under a collapsed Saved section has no row. A tab
    /// inside a collapsed folder shows as the outermost collapsed folder,
    /// unless that folder keeps the tab's own row. While the row is not laid
    /// out, an open folder around it leads the list toward it, or else where
    /// the row falls among the rows the list draws.
    @MainActor func location(
        in space: SpaceModel, reorder: BrowserSidebarReorderState, scrollRegionID: UUID
    ) -> SidebarScrollReveal.Location? {
        guard spaceID == space.id, let tab = space.tabs.model(tabID), !tab.placement.isGrid,
            !tab.placement.isCollapsible || space.settings.isSavedTabsExpanded
        else { return nil }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        func frame(_ item: BrowserSidebarReorderItemID) -> CGRect? {
            reorder.registeredFrame(of: item, in: assignment, scrollRegionID: scrollRegionID)
        }
        var enclosing: [FolderStateModel] = []
        var folderID = tab.folderID
        while let id = folderID, !enclosing.contains(where: { $0.id == id }), let folder = space.folders.model(id) {
            enclosing.append(folder)
            folderID = folder.parentID
        }
        let collapsed = enclosing.lastIndex(where: \.isCollapsed)
        let rowID = collapsed.map { enclosing[$0].id } ?? tabID
        guard let estimate = Self.placement(of: rowID, in: space) else { return nil }
        guard let viewport = reorder.scrollRegionFrame(for: scrollRegionID) else { return .estimated(estimate) }
        if let row = frame(.tab(tabID)) ?? tab.splitGroupID.flatMap({ frame(.splitGroup($0)) }) {
            return .placed(row, viewport: viewport)
        }
        if let collapsed, let row = frame(.folder(enclosing[collapsed].id)) {
            return .placed(row, viewport: viewport)
        }
        let outside = enclosing[(collapsed.map { $0 + 1 } ?? 0)...]
        if let open = outside.lazy.compactMap({ frame(.folder($0.id)) }).first {
            return .leading(open, viewport: viewport, estimate: estimate)
        }
        return .estimated(estimate)
    }

    /// How far down the rows `space`'s list draws the row of `rowID` falls,
    /// from 0 at the top to 1 at the foot, or nil when the list draws none:
    /// the saved section while it is open, then the open one, each with the
    /// inside of every open folder.
    @MainActor private static func placement(of rowID: UUID, in space: SpaceModel) -> Double? {
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
        guard let index = rows.firstIndex(where: { $0.id == rowID || $0.members.contains(rowID) }) else { return nil }
        return (Double(index) + 0.5) / Double(rows.count)
    }
}
