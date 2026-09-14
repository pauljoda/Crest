import Foundation

enum BrowserBookmarkSourceAdapters {
    static func decodeSafari(
        _ data: Data,
        source: BrowserBookmarkMigrationSource,
        fallbackDate: Date
    ) throws -> BrowserBookmarkSpaceDraft {
        let root: Any
        do {
            root = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
        } catch {
            throw BrowserBookmarkMigrationError.invalidContents
        }
        guard let dictionary = root as? [String: Any],
            let children = dictionary["Children"] as? [Any]
        else {
            throw BrowserBookmarkMigrationError.invalidContents
        }
        var draft = BrowserBookmarkSpaceDraft(
            name: String(localized: source.importedSpaceName)
        )
        try appendSafariChildren(
            children,
            parentID: nil,
            depth: 0,
            fallbackDate: fallbackDate,
            draft: &draft
        )
        return draft
    }

    static func decodeChrome(
        _ data: Data,
        source: BrowserBookmarkMigrationSource,
        fallbackDate: Date
    ) throws -> BrowserBookmarkSpaceDraft {
        let root = try jsonDictionary(data)
        guard let roots = root["roots"] as? [String: Any] else {
            throw BrowserBookmarkMigrationError.invalidContents
        }
        var draft = BrowserBookmarkSpaceDraft(
            name: String(localized: source.importedSpaceName)
        )
        let preferredKeys = ["bookmark_bar", "other", "synced"]
        let remainingKeys = roots.keys.filter { !preferredKeys.contains($0) }.sorted()
        for key in preferredKeys + remainingKeys {
            guard let node = roots[key] as? [String: Any] else { continue }
            try appendChromeNode(
                node,
                parentID: nil,
                depth: 0,
                fallbackDate: fallbackDate,
                draft: &draft
            )
        }
        return draft
    }

    static func decodeFirefox(
        _ data: Data,
        source: BrowserBookmarkMigrationSource,
        fallbackDate: Date
    ) throws -> BrowserBookmarkSpaceDraft {
        let root = try jsonDictionary(data)
        guard let children = root["children"] as? [Any] else {
            throw BrowserBookmarkMigrationError.invalidContents
        }
        var draft = BrowserBookmarkSpaceDraft(
            name: String(localized: source.importedSpaceName)
        )
        try appendFirefoxChildren(
            children,
            parentID: nil,
            depth: 0,
            fallbackDate: fallbackDate,
            draft: &draft
        )
        return draft
    }

    static func decodeArc(
        _ data: Data,
        source: BrowserBookmarkMigrationSource,
        fallbackDate: Date
    ) throws -> [BrowserBookmarkSpaceDraft] {
        guard let document = ArcSidebarDocument(data: data) else {
            throw BrowserBookmarkMigrationError.invalidContents
        }

        var drafts: [BrowserBookmarkSpaceDraft] = []
        for container in document.containers {
            var itemsByID: [String: ArcSidebarDocument.Item] = [:]
            for item in container.items {
                guard let id = item.id else { continue }
                itemsByID[id] = item
            }

            for (index, space) in container.spaces.enumerated() {
                let fallbackName = "Arc Space \(index + 1)"
                let name = space.title ?? fallbackName
                var draft = BrowserBookmarkSpaceDraft(name: name)
                var visited: Set<String> = []
                let containerIDs = space.containerIDs + space.newContainerIDs
                for id in containerIDs {
                    try appendArcItem(
                        id,
                        itemsByID: itemsByID,
                        parentFolderID: nil,
                        depth: 0,
                        fallbackDate: fallbackDate,
                        visited: &visited,
                        draft: &draft
                    )
                }
                if !draft.bookmarks.isEmpty {
                    drafts.append(draft)
                }
            }
        }
        return drafts
    }

    private static func appendSafariChildren(
        _ children: [Any],
        parentID: UUID?,
        depth: Int,
        fallbackDate: Date,
        draft: inout BrowserBookmarkSpaceDraft
    ) throws {
        for rawChild in children {
            guard let child = rawChild as? [String: Any] else { continue }
            let type = child["WebBookmarkType"] as? String
            if type == "WebBookmarkTypeLeaf", let url = child["URLString"] as? String {
                let uriDictionary = child["URIDictionary"] as? [String: Any]
                let title =
                    uriDictionary?["title"] as? String
                    ?? child["Title"] as? String
                    ?? ""
                try draft.appendBookmark(
                    title: title,
                    url: url,
                    folderID: parentID,
                    addedAt: BrowserBookmarkValueSanitizer.date(
                        child["DateAdded"] ?? child["DateVisited"],
                        epoch: .adaptive,
                        fallback: fallbackDate
                    )
                )
                continue
            }

            guard let nestedChildren = child["Children"] as? [Any] else { continue }
            let title = child["Title"] as? String ?? "Untitled Folder"
            let folderID = try draft.appendFolder(
                title: title,
                parentID: parentID,
                depth: depth
            )
            try appendSafariChildren(
                nestedChildren,
                parentID: folderID,
                depth: depth + 1,
                fallbackDate: fallbackDate,
                draft: &draft
            )
        }
    }

    private static func appendChromeNode(
        _ node: [String: Any],
        parentID: UUID?,
        depth: Int,
        fallbackDate: Date,
        draft: inout BrowserBookmarkSpaceDraft
    ) throws {
        let type = node["type"] as? String
        if type == "url", let url = node["url"] as? String {
            try draft.appendBookmark(
                title: node["name"] as? String ?? "",
                url: url,
                folderID: parentID,
                addedAt: BrowserBookmarkValueSanitizer.date(
                    node["date_added"],
                    epoch: .windowsMicroseconds,
                    fallback: fallbackDate
                )
            )
            return
        }
        guard type == "folder" || node["children"] != nil,
            let children = node["children"] as? [Any]
        else { return }
        let folderID = try draft.appendFolder(
            title: node["name"] as? String ?? "Untitled Folder",
            parentID: parentID,
            depth: depth
        )
        for rawChild in children {
            guard let child = rawChild as? [String: Any] else { continue }
            try appendChromeNode(
                child,
                parentID: folderID,
                depth: depth + 1,
                fallbackDate: fallbackDate,
                draft: &draft
            )
        }
    }

    private static func appendFirefoxChildren(
        _ children: [Any],
        parentID: UUID?,
        depth: Int,
        fallbackDate: Date,
        draft: inout BrowserBookmarkSpaceDraft
    ) throws {
        for rawChild in children {
            guard let child = rawChild as? [String: Any] else { continue }
            if let uri = child["uri"] as? String {
                try draft.appendBookmark(
                    title: child["title"] as? String ?? "",
                    url: uri,
                    folderID: parentID,
                    addedAt: BrowserBookmarkValueSanitizer.date(
                        child["dateAdded"],
                        epoch: .unixMicroseconds,
                        fallback: fallbackDate
                    )
                )
                continue
            }
            guard let nestedChildren = child["children"] as? [Any] else { continue }
            let folderID = try draft.appendFolder(
                title: child["title"] as? String ?? "Untitled Folder",
                parentID: parentID,
                depth: depth
            )
            try appendFirefoxChildren(
                nestedChildren,
                parentID: folderID,
                depth: depth + 1,
                fallbackDate: fallbackDate,
                draft: &draft
            )
        }
    }

    private static func appendArcItem(
        _ id: String,
        itemsByID: [String: ArcSidebarDocument.Item],
        parentFolderID: UUID?,
        depth: Int,
        fallbackDate: Date,
        visited: inout Set<String>,
        draft: inout BrowserBookmarkSpaceDraft
    ) throws {
        guard visited.insert(id).inserted,
            let item = itemsByID[id],
            let content = item.content
        else { return }

        if let tab = content.tab,
            let url = tab.url
        {
            try draft.appendBookmark(
                title: tab.title,
                url: url,
                folderID: parentFolderID,
                addedAt: BrowserBookmarkValueSanitizer.date(
                    tab.lastActivatedAtValue,
                    epoch: .adaptive,
                    fallback: fallbackDate
                )
            )
            return
        }

        let children = item.childrenIDs
        if content.isFolder {
            let folderID = try draft.appendFolder(
                title: item.title ?? "Untitled Folder",
                parentID: parentFolderID,
                depth: depth
            )
            for childID in children {
                try appendArcItem(
                    childID,
                    itemsByID: itemsByID,
                    parentFolderID: folderID,
                    depth: depth + 1,
                    fallbackDate: fallbackDate,
                    visited: &visited,
                    draft: &draft
                )
            }
            return
        }

        for childID in children {
            try appendArcItem(
                childID,
                itemsByID: itemsByID,
                parentFolderID: parentFolderID,
                depth: depth,
                fallbackDate: fallbackDate,
                visited: &visited,
                draft: &draft
            )
        }
    }

    private static func jsonDictionary(_ data: Data) throws -> [String: Any] {
        do {
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw BrowserBookmarkMigrationError.invalidContents
            }
            return root
        } catch let error as BrowserBookmarkMigrationError {
            throw error
        } catch {
            throw BrowserBookmarkMigrationError.invalidContents
        }
    }
}
