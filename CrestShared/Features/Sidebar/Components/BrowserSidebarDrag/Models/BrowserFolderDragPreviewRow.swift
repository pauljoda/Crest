import CoreGraphics

/// A visible part of a lifted folder, kept at its measured position.
struct BrowserFolderDragPreviewRow: Identifiable {
    enum Content {
        case tab(TabStateModel)
        case folder(FolderStateModel, depth: Int)
        case splitGroup([TabStateModel])
    }

    let id: BrowserSidebarReorderItemID
    let frame: CGRect
    let content: Content

    /// The rows of the lifted folder `rootFolderID` the reorder registry
    /// measured, with the objects each stands for in `space`.
    @MainActor
    static func resolve(
        _ rows: [BrowserSidebarReorderRow], in space: SpaceModel, rootFolderID: FolderID
    ) -> [Self] {
        let rootDepth = depth(of: rootFolderID, in: space)
        return rows.compactMap { row in
            let content: Content?
            switch row.id {
            case .tab(let id):
                content = space.tabs.model(id).map(Content.tab)
            case .folder(let id):
                content = space.folders.model(id).map {
                    .folder($0, depth: max(0, depth(of: id, in: space) - rootDepth))
                }
            case .splitGroup(let id):
                let members = space.splitMembers(of: id)
                content = members.isEmpty ? nil : .splitGroup(members)
            }
            return content.map { Self(id: row.id, frame: row.frame, content: $0) }
        }
    }

    /// How many folders hold the folder.
    @MainActor
    private static func depth(of folderID: FolderID, in space: SpaceModel) -> Int {
        var depth = 0
        var visited: Set<FolderID> = [folderID]
        var parent = space.folders.model(folderID)?.parentID
        while let id = parent, visited.insert(id).inserted {
            depth += 1
            parent = space.folders.model(id)?.parentID
        }
        return depth
    }
}
