extension BrowserCommandPaletteResults {
    static func savedResults(
        query: BrowserCommandPaletteQuery,
        space: BrowserSpace?
    ) -> [BrowserCommandPaletteResult] {
        guard !query.isEmpty, let space else { return [] }
        let tabs = space.tabs.filter { $0.placement != .current }
        let tree = space.folderTree
        let tabsByFolder = Dictionary(
            grouping: tabs.compactMap { tab in
                tab.folderID.map { ($0, tab) }
            }, by: \.0)

        var scored: [(BrowserCommandPaletteResult, Int)] = []
        for tab in tabs {
            guard !Task.isCancelled else { return [] }
            guard
                let score = BrowserCommandPaletteText.score(
                    query,
                    title: tab.displayTitle,
                    detail: tab.savedSiteURL?.absoluteString ?? tab.url?.absoluteString ?? ""
                )
            else { continue }
            scored.append(
                (
                    BrowserCommandPaletteResult(
                        section: .saved,
                        id: "saved-\(tab.id.id.uuidString)",
                        title: tab.displayTitle,
                        subtitle: savedSubtitle(for: tab, in: tree),
                        symbol: tab.placement == .pinned ? "pin.fill" : "bookmark",
                        trailing: "Switch to Tab",
                        target: .tab(
                            BrowserTabRuntimeAssignment(
                                tabID: tab.id,
                                spaceID: space.id,
                                profileID: space.profile.id
                            )
                        )
                    ),
                    score
                ))
        }

        for folder in tree.foldersInDisplayOrder {
            guard !Task.isCancelled else { return [] }
            guard
                let score = BrowserCommandPaletteText.score(
                    query,
                    title: folder.title,
                    detail: tree.pathTitle(for: folder.id) ?? ""
                )
            else { continue }
            let contents = tabsByFolder[folder.id, default: []].map { $0.1 }
            guard let first = contents.first else { continue }
            scored.append(
                (
                    BrowserCommandPaletteResult(
                        section: .saved,
                        id: "folder-\(folder.id.id.uuidString)",
                        title: folder.title,
                        subtitle: folderSubtitle(
                            count: contents.count,
                            path: tree.pathTitle(for: folder.id)
                        ),
                        symbol: folder.symbol,
                        trailing: "Open First Tab",
                        target: .tab(
                            BrowserTabRuntimeAssignment(
                                tabID: first.id,
                                spaceID: space.id,
                                profileID: space.profile.id
                            )
                        )
                    ),
                    score - BrowserCommandPaletteResultLimits.folderMatchPenalty
                ))
        }

        return
            scored
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.1 == rhs.element.1
                    ? lhs.offset < rhs.offset
                    : lhs.element.1 > rhs.element.1
            }
            .prefix(BrowserCommandPaletteResultLimits.saved)
            .map(\.element.0)
    }

    static func savedSubtitle(
        for tab: BrowserTab,
        in tree: BrowserFolderTree
    ) -> String {
        let host = tab.savedSiteURL?.host() ?? tab.url?.host() ?? ""
        guard let folderID = tab.folderID,
            let path = tree.pathTitle(for: folderID)
        else { return host }
        return host.isEmpty ? path : "\(path) · \(host)"
    }

    static func folderSubtitle(count: Int, path: String?) -> String {
        let tabs = count == 1 ? "1 tab" : "\(count) tabs"
        guard let path, path.contains("›") else { return tabs }
        return "\(path) · \(tabs)"
    }
}
