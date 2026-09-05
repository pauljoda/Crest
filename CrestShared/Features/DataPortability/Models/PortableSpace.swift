import Foundation

struct PortableSpace: Codable, Equatable, Sendable {
    let name: String
    let symbol: String
    let accent: SpaceAccent
    let branding: BrowserSpaceBranding?
    let folders: [PortableFolder]
    let tabs: [PortableTab]
    let splitGroups: [PortableSplitGroupMetadata]?
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
        splitGroups = space.splitGroups.map(PortableSplitGroupMetadata.init)
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

        let sourceSplitGroupIDs = Set(tabs.compactMap(\.splitGroupID))
        let splitGroupIDsBySourceID = Dictionary(
            uniqueKeysWithValues: sourceSplitGroupIDs.map {
                ($0, SplitGroupID())
            }
        )
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
                folderIDsBySourceID: folderIDsBySourceID,
                splitGroupIDsBySourceID: splitGroupIDsBySourceID
            )
            tabIDsBySourceID[tab.id] = materialized.id
            materializedTabs.append(materialized)
        }

        if materializedTabs.isEmpty {
            materializedTabs = [BrowserTab.startPage()]
        }
        guard
            BrowserSplitGroupNormalizer.normalized(materializedTabs)
                == materializedTabs
        else {
            throw BrowserPortableArchiveError.invalidContents
        }

        var seenSplitGroupMetadataIDs: Set<UUID> = []
        let materializedSplitGroups = try (splitGroups ?? []).map { metadata in
            guard seenSplitGroupMetadataIDs.insert(metadata.id).inserted,
                let groupID = splitGroupIDsBySourceID[metadata.id]
            else {
                throw BrowserPortableArchiveError.invalidContents
            }
            return try metadata.materialize(id: groupID)
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
            folders: folderTree.foldersInDisplayOrder.map { source in
                var folder = source
                folder.orderAnchorTabID = source.orderAnchorTabID.flatMap { tabIDsBySourceID[$0.rawValue] }
                return folder
            },
            tabs: materializedTabs,
            splitGroups: materializedSplitGroups,
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

/// Portable copy of group identity. Group IDs are source UUIDs in an archive
/// and are remapped alongside tab membership on import, so importing the same
/// archive twice cannot alias two live groups.
struct PortableSplitGroupMetadata: Codable, Equatable, Sendable {
    let id: UUID
    let customTitle: String?
    let titleModifiedAt: Date?
    let customIconSymbol: String?
    let iconModifiedAt: Date?
    let tint: BrowserSpaceBrandColor?
    let tintModifiedAt: Date?

    init(_ metadata: BrowserSplitGroupMetadata) {
        id = metadata.id.rawValue
        customTitle = metadata.customTitle
        titleModifiedAt = metadata.titleModifiedAt
        customIconSymbol = metadata.customIconSymbol
        iconModifiedAt = metadata.iconModifiedAt
        tint = metadata.tint
        tintModifiedAt = metadata.tintModifiedAt
    }

    func materialize(id: SplitGroupID) throws -> BrowserSplitGroupMetadata {
        if let customTitle {
            try ArchiveValidation.requireText(
                customTitle,
                maximumLength: ArchiveLimits.maximumTabTitleLength
            )
        }
        if let customIconSymbol {
            try ArchiveValidation.requireText(
                customIconSymbol,
                maximumLength: ArchiveLimits.maximumSymbolLength
            )
            guard BrowserIconSymbol.emoji(from: customIconSymbol) != nil else {
                throw BrowserPortableArchiveError.invalidContents
            }
        }
        for date in [titleModifiedAt, iconModifiedAt, tintModifiedAt] {
            if let date { try ArchiveValidation.requireDate(date) }
        }
        return BrowserSplitGroupMetadata(
            id: id,
            customTitle: customTitle,
            titleModifiedAt: titleModifiedAt,
            customIconSymbol: customIconSymbol,
            iconModifiedAt: iconModifiedAt,
            tint: tint,
            tintModifiedAt: tintModifiedAt
        )
    }
}
