import Foundation

struct BrowserBookmarkSpaceDraft: Equatable, Sendable {
    var name: String
    private(set) var folders: [BrowserBookmarkFolderDraft] = []
    private(set) var bookmarks: [BrowserBookmarkDraft] = []

    init(name: String) {
        self.name = name
    }

    mutating func appendFolder(
        title: String,
        parentID: UUID?,
        depth: Int
    ) throws -> UUID {
        guard depth < BrowserSpace.maximumFolderDepth,
            folders.count < BrowserSpace.maximumFolderCount
        else {
            throw BrowserBookmarkMigrationError.resourceLimitExceeded
        }
        let normalizedTitle = try BrowserBookmarkValueSanitizer.title(
            title,
            fallback: "Untitled Folder",
            maximumLength: 500
        )
        let folder = BrowserBookmarkFolderDraft(
            id: UUID(),
            title: normalizedTitle,
            parentID: parentID
        )
        folders.append(folder)
        return folder.id
    }

    mutating func appendBookmark(
        title: String,
        url sourceURL: String,
        folderID: UUID?,
        addedAt: Date
    ) throws {
        guard bookmarks.count < 5_000 else {
            throw BrowserBookmarkMigrationError.resourceLimitExceeded
        }
        guard let url = BrowserBookmarkValueSanitizer.url(sourceURL) else { return }
        let normalizedTitle = try BrowserBookmarkValueSanitizer.title(
            title,
            fallback: url.host ?? url.absoluteString,
            maximumLength: 4_096
        )
        bookmarks.append(
            BrowserBookmarkDraft(
                title: normalizedTitle,
                url: url,
                folderID: folderID,
                addedAt: addedAt.timeIntervalSinceReferenceDate.isFinite ? addedAt : .now
            )
        )
    }

    func makeTemporarySpace(
        source: BrowserBookmarkMigrationSource
    ) throws -> BrowserSpace {
        var folderIDs: [UUID: FolderID] = [:]
        for folder in folders {
            folderIDs[folder.id] = FolderID()
        }
        let materializedFolders = try folders.map { folder -> BrowserFolder in
            let parentID: FolderID?
            if let sourceParentID = folder.parentID {
                guard let mappedParentID = folderIDs[sourceParentID] else {
                    throw BrowserBookmarkMigrationError.invalidContents
                }
                parentID = mappedParentID
            } else {
                parentID = nil
            }
            guard let id = folderIDs[folder.id] else {
                throw BrowserBookmarkMigrationError.invalidContents
            }
            return BrowserFolder(
                id: id,
                title: folder.title,
                symbol: "folder",
                parentID: parentID
            )
        }
        let folderTree = BrowserFolderTree(folders: materializedFolders)
        guard folderTree.isValid else {
            throw BrowserBookmarkMigrationError.resourceLimitExceeded
        }

        let tabs = bookmarks.map { bookmark in
            BrowserTab(
                title: bookmark.title,
                url: bookmark.url,
                symbol: "book.closed",
                placement: .saved,
                folderID: bookmark.folderID.flatMap { folderIDs[$0] },
                lastActivatedAt: bookmark.addedAt
            )
        }
        guard let selectedTabID = tabs.first?.id else {
            throw BrowserBookmarkMigrationError.noImportableBookmarks
        }
        let normalizedName = try BrowserBookmarkValueSanitizer.title(
            name,
            fallback: String(localized: source.importedSpaceName),
            maximumLength: 200
        )

        return BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: normalizedName,
            symbol: source.symbol,
            accent: source.accent,
            folders: folderTree.foldersInDisplayOrder,
            tabs: tabs,
            archivedTabs: [],
            history: [],
            browsingPreferences: .default,
            credentialPreferences: .default,
            selectedTabID: selectedTabID
        )
    }
}
