import Foundation

struct PortableSpace: Codable, Equatable, Sendable {
    let name: String
    let symbol: String
    let accent: SpaceAccent
    let branding: BrowserSpaceBranding?
    let folders: [PortableFolder]
    let tabs: [PortableTab]
    let archivedTabs: [PortableArchivedTab]
    let history: [PortableHistoryEntry]
    let browsingPreferences: BrowserSpaceBrowsingPreferences
    let selectedTabID: UUID?

    init(_ space: BrowserSpace) {
        name = space.name
        symbol = space.symbol
        accent = space.accent
        branding = space.branding
        folders = space.folders.map(PortableFolder.init)
        tabs = space.tabs.map(PortableTab.init)
        archivedTabs = space.archivedTabs.map(PortableArchivedTab.init)
        history = space.history.map(PortableHistoryEntry.init)
        browsingPreferences = space.browsingPreferences
        selectedTabID = space.selectedTabID?.rawValue
    }

    func materialize() throws -> BrowserSpace {
        try ArchiveValidation.requireText(name, maximumLength: ArchiveLimits.maximumSpaceNameLength)
        try ArchiveValidation.requireText(symbol, maximumLength: ArchiveLimits.maximumSymbolLength)
        guard folders.count <= ArchiveLimits.maximumFoldersPerSpace,
            tabs.count <= ArchiveLimits.maximumLiveTabsPerSpace,
            archivedTabs.count <= ArchiveLimits.maximumArchivedTabsPerSpace,
            history.count <= ArchiveLimits.maximumHistoryEntriesPerSpace
        else {
            throw BrowserPortableArchiveError.invalidContents
        }

        var folderIDsBySourceID: [UUID: FolderID] = [:]
        for folder in folders {
            guard folderIDsBySourceID[folder.id] == nil else {
                throw BrowserPortableArchiveError.invalidContents
            }
            folderIDsBySourceID[folder.id] = FolderID()
        }
        let materializedFolders = try folders.map { folder in
            guard let materializedID = folderIDsBySourceID[folder.id] else {
                throw BrowserPortableArchiveError.invalidContents
            }
            let parentID: FolderID?
            if let sourceParentID = folder.parentID {
                guard sourceParentID != folder.id,
                    let mappedParentID = folderIDsBySourceID[sourceParentID]
                else {
                    throw BrowserPortableArchiveError.invalidContents
                }
                parentID = mappedParentID
            } else {
                parentID = nil
            }
            return try folder.materialize(
                id: materializedID,
                parentID: parentID
            )
        }
        let folderTree = BrowserFolderTree(folders: materializedFolders)
        guard folderTree.isValid else {
            throw BrowserPortableArchiveError.invalidContents
        }

        var tabIDsBySourceID: [UUID: TabID] = [:]
        var materializedTabs: [BrowserTab] = []
        materializedTabs.reserveCapacity(max(tabs.count, 1))
        var pinnedCount = 0
        for tab in tabs {
            guard tabIDsBySourceID[tab.id] == nil else {
                throw BrowserPortableArchiveError.invalidContents
            }
            if tab.placement == .pinned {
                pinnedCount += 1
                guard pinnedCount <= BrowserSpace.maximumPinnedTabs else {
                    throw BrowserPortableArchiveError.invalidContents
                }
            }
            let materialized = try tab.materialize(
                folderIDsBySourceID: folderIDsBySourceID
            )
            tabIDsBySourceID[tab.id] = materialized.id
            materializedTabs.append(materialized)
        }

        if materializedTabs.isEmpty {
            materializedTabs = [BrowserTab.startPage()]
        }

        var seenArchivedTabIDs: Set<UUID> = []
        let materializedArchive = try archivedTabs.map { archived in
            guard seenArchivedTabIDs.insert(archived.tab.id).inserted,
                tabIDsBySourceID[archived.tab.id] == nil
            else {
                throw BrowserPortableArchiveError.invalidContents
            }
            return try archived.materialize()
        }
        let materializedHistory = try Self.materializeHistory(history)

        let selectedID: TabID?
        if let selectedTabID {
            guard let mappedID = tabIDsBySourceID[selectedTabID] else {
                throw BrowserPortableArchiveError.invalidContents
            }
            selectedID = mappedID
        } else {
            selectedID = materializedTabs.first?.id
        }

        return BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: name,
            symbol: symbol,
            accent: accent,
            branding: branding,
            folders: folderTree.foldersInDisplayOrder,
            tabs: materializedTabs,
            archivedTabs: materializedArchive,
            history: materializedHistory,
            browsingPreferences: browsingPreferences,
            credentialPreferences: .default,
            selectedTabID: selectedID
        )
    }

    private static func materializeHistory(
        _ source: [PortableHistoryEntry]
    ) throws -> [BrowserHistoryEntry] {
        var entriesByURL: [URL: BrowserHistoryEntry] = [:]
        for entry in source {
            let materialized = try entry.materialize()
            if var existing = entriesByURL[materialized.url] {
                let combinedVisitCount = existing.visitCount.addingReportingOverflow(
                    materialized.visitCount
                )
                guard !combinedVisitCount.overflow else {
                    throw BrowserPortableArchiveError.invalidContents
                }
                existing = BrowserHistoryEntry(
                    url: existing.url,
                    title: materialized.lastVisitedAt >= existing.lastVisitedAt
                        ? materialized.title
                        : existing.title,
                    firstVisitedAt: min(existing.firstVisitedAt, materialized.firstVisitedAt),
                    lastVisitedAt: max(existing.lastVisitedAt, materialized.lastVisitedAt),
                    visitCount: combinedVisitCount.partialValue
                )
                entriesByURL[materialized.url] = existing
            } else {
                entriesByURL[materialized.url] = materialized
            }
        }
        return entriesByURL.values
            .sorted {
                if $0.lastVisitedAt != $1.lastVisitedAt {
                    return $0.lastVisitedAt > $1.lastVisitedAt
                }
                return $0.url.absoluteString < $1.url.absoluteString
            }
            .prefix(BrowserSession.maximumHistoryEntriesPerSpace)
            .map(\.self)
    }
}
