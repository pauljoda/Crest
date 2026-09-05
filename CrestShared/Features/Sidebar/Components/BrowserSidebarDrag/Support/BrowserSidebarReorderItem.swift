/// Something the sidebar can reorder in place. Tabs, folders, and split groups
/// share the same lift, displacement, and drop-indicator machinery; only the
/// committed move differs.
enum BrowserSidebarReorderItem: Equatable, Sendable {
    case tab(BrowserTabDragItem)
    case folder(BrowserFolderDragItem)
    /// A whole split group. Its members are not individual drag sources while
    /// grouped, so the run can never be torn apart by a drop landing inside it.
    case splitGroup(BrowserSplitGroupDragItem)

    var id: BrowserSidebarReorderItemID {
        switch self {
        case .tab(let item): .tab(item.tabID)
        case .folder(let item): .folder(item.folderID)
        case .splitGroup(let item): .splitGroup(item.groupID)
        }
    }

    var spaceAssignment: BrowserSpaceRuntimeAssignment {
        switch self {
        case .tab(let item): item.spaceAssignment
        case .folder(let item): item.spaceAssignment
        case .splitGroup(let item): item.spaceAssignment
        }
    }
}

/// Identity for a reorderable row, so one registry can hold tabs, folders, and
/// split groups.
enum BrowserSidebarReorderItemID: Hashable, Sendable {
    case tab(TabID)
    case folder(FolderID)
    case splitGroup(SplitGroupID)

    var folderID: FolderID? {
        guard case .folder(let id) = self else { return nil }
        return id
    }

    var tabID: TabID? {
        guard case .tab(let id) = self else { return nil }
        return id
    }
}
