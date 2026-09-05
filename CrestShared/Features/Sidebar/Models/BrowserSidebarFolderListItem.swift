/// Merges top-level folders and unfiled tab rows using the session's tab order.
/// Nested folders are rendered by the same recursive folder component as Saved.
enum BrowserSidebarFolderListItem: Identifiable {
    case folder(BrowserFolderNode)
    case tabs(BrowserSidebarTabListItem)

    var id: BrowserSidebarReorderItemID {
        switch self {
        case .folder(let node): .folder(node.id)
        case .tabs(let item):
            switch item {
            case .tab(let tab): .tab(tab.id)
            case .splitGroup(let id, _): .splitGroup(id)
            }
        }
    }

    /// One projection per placement, shared by every recursive folder view.
    /// Each tab walks only its ancestor chain; descendants never rescan the
    /// whole Space merely to render their own direct children.
    struct Projection {
        private var sections: [FolderID?: [BrowserSidebarFolderListItem]] = [:]

        init(tabs: [BrowserTab], tree: BrowserFolderTree, location: BrowserFolderLocation) {
            let nodes = tree.flattenedNodes(collapsedFolderIDs: []).filter { $0.folder.location == location }
            let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
            var paths: [FolderID: [FolderID]] = [:]
            for node in nodes {
                paths[node.id] = (node.folder.parentID.flatMap { paths[$0] } ?? []) + [node.id]
            }
            let tabParents = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0.folderID) })
            var emitted: [FolderID?: Set<FolderID>] = [:]
            for item in BrowserSidebarTabListItemPolicy.items(
                for: tabs.filter { $0.placement == location.tabPlacement })
            {
                let parent = item.tabs.first?.folderID
                var ancestor: FolderID?
                for id in parent.flatMap({ paths[$0] }) ?? [] {
                    if let node = byID[id], emitted[ancestor, default: []].insert(id).inserted {
                        sections[ancestor, default: []].append(.folder(node))
                    }
                    ancestor = id
                }
                sections[parent, default: []].append(.tabs(item))
            }
            for node in nodes where !emitted[node.folder.parentID, default: []].contains(node.id) {
                let parent = node.folder.parentID
                let anchor = node.folder.orderAnchorTabID
                let anchorPath = anchor.flatMap { tabParents[$0] ?? nil }.flatMap { paths[$0] } ?? []
                let index =
                    sections[parent, default: []].firstIndex { item in
                        guard let anchor else { return false }
                        switch item {
                        case .tabs(let row): return row.tabs.contains { $0.id == anchor }
                        case .folder(let folder):
                            return anchorPath.contains(folder.id)
                        }
                    } ?? sections[parent, default: []].endIndex
                sections[parent, default: []].insert(.folder(node), at: index)
            }
        }

        func items(in parentID: FolderID? = nil) -> [BrowserSidebarFolderListItem] {
            sections[parentID] ?? []
        }
    }

    static func items(
        tabs: [BrowserTab], tree: BrowserFolderTree, location: BrowserFolderLocation, parentID: FolderID? = nil
    ) -> [Self] {
        Projection(tabs: tabs, tree: tree, location: location).items(in: parentID)
    }
}
