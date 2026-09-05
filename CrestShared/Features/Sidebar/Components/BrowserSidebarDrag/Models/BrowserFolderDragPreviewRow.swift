import CoreGraphics

/// A visible part of a lifted folder, kept at its measured position.
struct BrowserFolderDragPreviewRow: Equatable, Identifiable {
    enum Content: Equatable {
        case tab(BrowserTab)
        case folder(BrowserFolder, depth: Int)
        case splitGroup([BrowserTab])
    }

    let id: BrowserSidebarReorderItemID
    let frame: CGRect
    let content: Content

    static func resolve(
        _ rows: [BrowserSidebarReorderRow], in space: BrowserSpace, rootFolderID: FolderID
    ) -> [Self] {
        let tree = space.folderTree
        let rootDepth = tree.depth(of: rootFolderID) ?? 0
        return rows.compactMap { row in
            let content: Content?
            switch row.id {
            case .tab(let id):
                content = space.tabs.first { $0.id == id }.map(Content.tab)
            case .folder(let id):
                content = space.folders.first { $0.id == id }.map {
                    .folder($0, depth: max(0, (tree.depth(of: id) ?? rootDepth) - rootDepth))
                }
            case .splitGroup(let id):
                let members = space.splitGroupMembers(of: id)
                content = members.isEmpty ? nil : .splitGroup(members)
            }
            return content.map { Self(id: row.id, frame: row.frame, content: $0) }
        }
    }
}
