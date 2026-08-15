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
        case let .tab(item): .tab(item.tabID)
        case let .folder(item): .folder(item.folderID)
        case let .splitGroup(item): .splitGroup(item.groupID)
        }
    }

    var spaceAssignment: BrowserSpaceRuntimeAssignment {
        switch self {
        case let .tab(item): item.spaceAssignment
        case let .folder(item): item.spaceAssignment
        case let .splitGroup(item): item.spaceAssignment
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
        guard case let .folder(id) = self else { return nil }
        return id
    }

    var tabID: TabID? {
        guard case let .tab(id) = self else { return nil }
        return id
    }
}
