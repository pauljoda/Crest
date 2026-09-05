import Foundation

enum BrowserTabMigration {
    static let maximumEncodedByteCount = 512 * 1_024 * 1_024
    static let maximumDecodedByteCount = BrowserPortableArchive.maximumEncodedByteCount
    static let maximumTabCountPerSpace = 5_000

    static func decode(
        _ data: Data,
        source: BrowserTabMigrationSource,
        importedAt: Date = .now
    ) throws -> BrowserPortableImport {
        guard data.count <= maximumEncodedByteCount else {
            throw BrowserTabMigrationError.fileTooLarge
        }

        let drafts: [BrowserTabSessionDraft]
        do {
            switch source {
            case .safari:
                drafts = try SafariTabSessionAdapter.decode(data, importedAt: importedAt)
            case .chrome:
                drafts = try ChromiumTabSessionAdapter.decode(data, importedAt: importedAt)
            case .firefox:
                drafts = try FirefoxTabSessionAdapter.decode(data, importedAt: importedAt)
            case .arc:
                drafts = try ArcTabSessionAdapter.decode(data, importedAt: importedAt)
            case .zen:
                drafts = try ZenTabSessionAdapter.decode(data, importedAt: importedAt)
            }
        } catch let error as BrowserTabMigrationError {
            throw error
        } catch let error as BrowserBookmarkMigrationError {
            switch error {
            case .fileTooLarge, .resourceLimitExceeded:
                throw BrowserTabMigrationError.resourceLimitExceeded
            case .invalidContents, .noImportableBookmarks:
                throw BrowserTabMigrationError.invalidContents
            }
        } catch {
            throw BrowserTabMigrationError.invalidContents
        }
        return try materialize(drafts, source: source, importedAt: importedAt)
    }

    private static func materialize(
        _ sourceDrafts: [BrowserTabSessionDraft],
        source: BrowserTabMigrationSource,
        importedAt: Date
    ) throws -> BrowserPortableImport {
        let drafts = sourceDrafts.filter { !$0.tabs.isEmpty }
        guard !drafts.isEmpty else {
            throw BrowserTabMigrationError.noImportableTabs
        }
        guard drafts.count <= BrowserPortableArchive.maximumSpaceCount,
            drafts.allSatisfy({ $0.tabs.count <= maximumTabCountPerSpace })
        else {
            throw BrowserTabMigrationError.resourceLimitExceeded
        }

        let spaces = try drafts.map { draft in
            try makeTemporarySpace(
                draft,
                source: source,
                usesWindowSuffix: drafts.count > 1,
                importedAt: importedAt
            )
        }
        do {
            return try BrowserPortableArchive(
                session: BrowserSession(
                    spaces: spaces,
                    selectedSpaceID: spaces[0].id
                ),
                exportedAt: importedAt
            ).materialize()
        } catch {
            throw BrowserTabMigrationError.resourceLimitExceeded
        }
    }

    private static func makeTemporarySpace(
        _ draft: BrowserTabSessionDraft,
        source: BrowserTabMigrationSource,
        usesWindowSuffix: Bool,
        importedAt: Date
    ) throws -> BrowserSpace {
        guard draft.folders.count < BrowserSpace.maximumFolderCount else {
            throw BrowserTabMigrationError.resourceLimitExceeded
        }
        var folderIDsBySourceID: [String: FolderID] = [:]
        for folder in draft.folders {
            guard folderIDsBySourceID[folder.sourceID] == nil else {
                throw BrowserTabMigrationError.invalidContents
            }
            folderIDsBySourceID[folder.sourceID] = FolderID()
        }
        var folders = try draft.folders.map { folder -> BrowserFolder in
            let parentID: FolderID?
            if let parentSourceID = folder.parentSourceID {
                guard parentSourceID != folder.sourceID,
                    let resolvedParentID = folderIDsBySourceID[parentSourceID]
                else {
                    throw BrowserTabMigrationError.invalidContents
                }
                parentID = resolvedParentID
            } else {
                parentID = nil
            }
            guard let id = folderIDsBySourceID[folder.sourceID] else {
                throw BrowserTabMigrationError.invalidContents
            }
            return BrowserFolder(
                id: id,
                title: try BrowserTabMigrationSanitizer.title(
                    folder.title,
                    fallback: "Untitled Folder",
                    maximumLength: 500
                ),
                symbol: "folder",
                parentID: parentID
            )
        }
        guard BrowserFolderTree(folders: folders).isValid else {
            throw BrowserTabMigrationError.resourceLimitExceeded
        }

        var pinnedCount = 0
        var overflowFolderID: FolderID?
        var tabs: [BrowserTab] = []
        tabs.reserveCapacity(draft.tabs.count)
        for sourceTab in draft.tabs {
            var placement = sourceTab.placement
            var folderID = sourceTab.folderSourceID.flatMap { folderIDsBySourceID[$0] }
            if placement == .saved,
                sourceTab.folderSourceID != nil,
                folderID == nil
            {
                throw BrowserTabMigrationError.invalidContents
            }
            if placement == .pinned, pinnedCount < BrowserSpace.maximumPinnedTabs {
                pinnedCount += 1
            } else if placement == .pinned {
                placement = .saved
                if overflowFolderID == nil {
                    let folder = BrowserFolder(
                        title: "Imported Pinned Tabs",
                        symbol: "pin.slash"
                    )
                    folders.append(folder)
                    overflowFolderID = folder.id
                }
                folderID = overflowFolderID
            }
            tabs.append(
                BrowserTab(
                    title: try BrowserTabMigrationSanitizer.title(
                        sourceTab.title,
                        fallback: sourceTab.url.host ?? sourceTab.url.absoluteString
                    ),
                    url: sourceTab.url,
                    symbol: placement == .pinned ? "pin.fill" : "globe",
                    placement: placement,
                    folderID: placement == .saved ? folderID : nil,
                    lastActivatedAt: sourceTab.lastActivatedAt
                        .timeIntervalSinceReferenceDate.isFinite
                        ? sourceTab.lastActivatedAt
                        : importedAt
                ))
        }
        let fallbackName =
            usesWindowSuffix
            ? windowName(source: source, ordinal: draft.sourceOrdinal)
            : String(localized: source.importedSpaceName)
        let name = try BrowserTabMigrationSanitizer.title(
            draft.name ?? "",
            fallback: fallbackName,
            maximumLength: 200
        )
        let selectedIndex = min(max(0, draft.selectedTabIndex ?? 0), tabs.count - 1)
        return BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: name,
            symbol: draft.symbol ?? source.symbol,
            accent: draft.accent ?? source.accent,
            branding: draft.branding
                ?? .neutralImport(
                    symbol: draft.symbol ?? source.symbol
                ),
            folders: BrowserFolderTree(folders: folders).foldersInDisplayOrder,
            tabs: tabs,
            archivedTabs: [],
            history: [],
            browsingPreferences: .default,
            credentialPreferences: .default,
            selectedTabID: tabs[selectedIndex].id
        )
    }

    private static func windowName(
        source: BrowserTabMigrationSource,
        ordinal: Int
    ) -> String {
        switch source {
        case .safari:
            String(localized: "Imported Safari Window \(ordinal)")
        case .chrome:
            String(localized: "Imported Chrome Window \(ordinal)")
        case .firefox:
            String(localized: "Imported Firefox Window \(ordinal)")
        case .arc:
            String(localized: "Imported Arc Space \(ordinal)")
        case .zen:
            String(localized: "Imported Zen Space \(ordinal)")
        }
    }
}
