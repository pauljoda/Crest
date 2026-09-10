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

    var selection: BrowserTabBatchRequest? {
        switch self {
        case .tab(let item): item.selection
        case .splitGroup(let item): item.selection
        case .folder(let item): item.selection
        }
    }

    func selecting(_ request: BrowserTabBatchRequest?) -> Self {
        switch self {
        case .tab(var item):
            item.selection = request
            return .tab(item)
        case .splitGroup(var item):
            item.selection = request
            return .splitGroup(item)
        case .folder(var item):
            item.selection = request
            return .folder(item)
        }
    }

    var selectionRowIDs: Set<BrowserSidebarReorderItemID> {
        guard let selection else { return [id] }
        let members = Dictionary(uniqueKeysWithValues: selection.members.map { ($0.id, $0) })
        return Set(
            selection.rootItems.map {
                switch $0 {
                case .folder(let id): return .folder(id)
                case .tab(let id):
                    if let member = members[id], let group = member.splitGroupID, member.placement != .pinned {
                        return .splitGroup(group)
                    }
                    return .tab(id)
                }
            })
    }

    var selectionHiddenRowIDs: Set<BrowserSidebarReorderItemID> {
        guard let selection else { return [id] }
        return selectionRowIDs.union(selection.folderIDs.map(Self.folderRowID))
            .union(
                selection.members.map { member in
                    member.splitGroupID.map(BrowserSidebarReorderItemID.splitGroup) ?? .tab(member.id)
                })
    }

    private static func folderRowID(_ id: FolderID) -> BrowserSidebarReorderItemID { .folder(id) }

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
