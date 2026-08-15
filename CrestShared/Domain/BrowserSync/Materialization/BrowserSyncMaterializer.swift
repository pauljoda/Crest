import Foundation

enum BrowserSyncMaterializer {
    static func materialize(
        records: [BrowserSyncRecord],
        preferences: BrowserSyncPreferences,
        localSession: BrowserSession
    ) throws -> BrowserSession {
        let active = records.filter { $0.payload != nil }
        let folderRecordSpaceIDs = Self.folderRecordSpaceIDs(in: records)
        let spaceRecords = active.compactMap { record -> BrowserSyncSpace? in
            guard case .space(let space)? = record.payload else { return nil }
            return space
        }.sorted(by: ordered)
        let activeSpaceIDs = Set(spaceRecords.map(\.id))
        var seenProfiles: Set<UUID> = []
        var spaces: [BrowserSpace] = []

        for syncedSpace in spaceRecords {
            guard seenProfiles.insert(syncedSpace.profileID).inserted else {
                throw BrowserSyncError.duplicateProfile(syncedSpace.profileID)
            }
            let local = localSession.space(id: syncedSpace.id)
            if let local, local.profile.id != syncedSpace.profileID {
                throw BrowserSyncError.immutableProfileChanged(syncedSpace.id)
            }

            let folders = try materializedFolders(
                spaceID: syncedSpace.id,
                records: active,
                preferences: preferences,
                local: local,
                folderRecordSpaceIDs: folderRecordSpaceIDs
            )
            let tabs = try materializedTabs(
                spaceID: syncedSpace.id,
                records: active,
                preferences: preferences,
                local: local,
                folders: folders,
                folderRecordSpaceIDs: folderRecordSpaceIDs
            )
            let archive = materializedArchive(
                spaceID: syncedSpace.id,
                records: active,
                preferences: preferences,
                local: local,
                activeTabs: tabs
            )
            let history = materializedHistory(
                spaceID: syncedSpace.id,
                records: active,
                preferences: preferences,
                local: local
            )
            let usableTabs =
                tabs.isEmpty
                ? [BrowserTab.startPage()]
                : tabs
            let selectedTabID = local?.selectedTabID.flatMap { selected in
                usableTabs.contains(where: { $0.id == selected }) ? selected : nil
            }

            spaces.append(
                BrowserSpace(
                    id: syncedSpace.id,
                    profile: BrowsingProfile(id: syncedSpace.profileID),
                    name: syncedSpace.name,
                    symbol: syncedSpace.symbol,
                    accent: syncedSpace.accent,
                    branding: syncedSpace.branding,
                    folders: folders,
                    tabs: usableTabs,
                    archivedTabs: archive,
                    history: history,
                    browsingPreferences: syncedSpace.browsingPreferences,
                    credentialPreferences: local?.credentialPreferences ?? .default,
                    accessPolicy: syncedSpace.accessPolicy,
                    isSavedTabsExpanded: syncedSpace.isSavedTabsExpanded,
                    savedTabsExpansionModifiedAt: syncedSpace
                        .savedTabsExpansionModifiedAt,
                    selectedTabID: selectedTabID
                ))
        }

        if spaces.isEmpty {
            var fallback = localSession
            fallback.repairRuntimeIntegrity()
            return fallback
        }

        let selectedSpaceID =
            activeSpaceIDs.contains(localSession.selectedSpaceID)
            ? localSession.selectedSpaceID
            : spaces[0].id
        var result = BrowserSession(spaces: spaces, selectedSpaceID: selectedSpaceID)
        result.defaultSpaceID = localSession.defaultSpaceID
        result.repairRuntimeIntegrity()
        return result
    }

    /// The Space each folder record belongs to, whether that folder is still
    /// present or already tombstoned.
    ///
    /// This is how a saved tab's missing folder is told apart from a deleted one:
    /// a folder somebody deleted keeps a record of its own, and a folder whose
    /// record has not arrived yet has none.
    private static func folderRecordSpaceIDs(
        in records: [BrowserSyncRecord]
    ) -> [FolderID: SpaceID] {
        var result: [FolderID: SpaceID] = [:]
        for record in records where record.id.kind == .folder {
            result[FolderID(rawValue: record.id.value)] = record.spaceID
        }
        return result
    }

    /// Builds the folder tree this Space's records describe.
    ///
    /// A folder whose parent record has not arrived yet is held back with its
    /// whole subtree instead of failing the fetch. Every synced folder still has
    /// to be accounted for — materialized or deliberately held back — so a folder
    /// left unreachable by a cycle is as fatal as it always was.
    private static func materializedFolders(
        spaceID: SpaceID,
        records: [BrowserSyncRecord],
        preferences: BrowserSyncPreferences,
        local: BrowserSpace?,
        folderRecordSpaceIDs: [FolderID: SpaceID]
    ) throws -> [SavedFolder] {
        guard preferences.savedStructure else { return local?.folders ?? [] }
        let synced = records.compactMap { record -> BrowserSyncFolder? in
            guard case .folder(let folder)? = record.payload, folder.spaceID == spaceID else { return nil }
            return folder
        }
        guard synced.count <= BrowserSpace.maximumFolderCount else {
            throw BrowserSyncError.invalidFolderHierarchy(spaceID)
        }

        let foldersByID = Dictionary(uniqueKeysWithValues: synced.map { ($0.id, $0) })
        var childrenByParentID: [FolderID: [BrowserSyncFolder]] = [:]
        var roots: [BrowserSyncFolder] = []
        var waitingForAParent: Set<FolderID> = []
        for folder in synced {
            guard let parentID = folder.parentID else {
                roots.append(folder)
                continue
            }
            guard parentID != folder.id else {
                throw BrowserSyncError.invalidFolderHierarchy(spaceID)
            }
            guard foldersByID[parentID] != nil else {
                // A parent recorded in another Space is not something delivery
                // order can explain, so it still fails closed.
                guard (folderRecordSpaceIDs[parentID] ?? spaceID) == spaceID else {
                    throw BrowserSyncError.invalidFolderHierarchy(spaceID)
                }
                // Either the parent has not arrived yet or somebody deleted it.
                // Both mean this folder is not part of the Space right now, and
                // holding it back costs nothing: its record is untouched, so
                // `stage` keeps it while the parent is still on its way and
                // tombstones it once the parent is gone.
                waitingForAParent.insert(folder.id)
                continue
            }
            childrenByParentID[parentID, default: []].append(folder)
        }
        roots.sort(by: ordered)
        for parentID in childrenByParentID.keys {
            childrenByParentID[parentID]?.sort(by: ordered)
        }

        var visited: Set<FolderID> = []
        var materialized: [SavedFolder] = []
        func append(_ folder: BrowserSyncFolder, depth: Int) throws {
            guard depth < BrowserSpace.maximumFolderDepth,
                visited.insert(folder.id).inserted
            else {
                throw BrowserSyncError.invalidFolderHierarchy(spaceID)
            }
            materialized.append(
                SavedFolder(
                    id: folder.id,
                    title: folder.title,
                    symbol: folder.symbol,
                    color: folder.color,
                    parentID: folder.parentID,
                    isCollapsed: folder.isCollapsed,
                    collapseModifiedAt: folder.collapseModifiedAt
                ))
            for child in childrenByParentID[folder.id] ?? [] {
                try append(child, depth: depth + 1)
            }
        }
        for root in roots {
            try append(root, depth: 0)
        }
        let heldBack = heldBackSubtrees(
            waitingForAParent: waitingForAParent,
            childrenByParentID: childrenByParentID
        )
        // Every synced folder is either in the tree or knowingly waiting for an
        // ancestor. A folder that is neither — one a cycle left unreachable — is
        // the corruption this check exists to catch.
        guard visited.count + heldBack.count == synced.count,
            BrowserFolderTree(folders: materialized).isValid
        else {
            throw BrowserSyncError.invalidFolderHierarchy(spaceID)
        }
        return materialized
    }

    /// The folders waiting for an ancestor, plus everything beneath them.
    ///
    /// A folder can only name one parent, so descending from a folder that is
    /// itself waiting can never re-enter a cycle; the visited check is there to
    /// keep that true rather than assumed.
    private static func heldBackSubtrees(
        waitingForAParent: Set<FolderID>,
        childrenByParentID: [FolderID: [BrowserSyncFolder]]
    ) -> Set<FolderID> {
        var heldBack = waitingForAParent
        var pending = Array(waitingForAParent)
        while let folderID = pending.popLast() {
            for child in childrenByParentID[folderID] ?? [] {
                guard heldBack.insert(child.id).inserted else { continue }
                pending.append(child.id)
            }
        }
        return heldBack
    }

    private static func materializedTabs(
        spaceID: SpaceID,
        records: [BrowserSyncRecord],
        preferences: BrowserSyncPreferences,
        local: BrowserSpace?,
        folders: [SavedFolder],
        folderRecordSpaceIDs: [FolderID: SpaceID]
    ) throws -> [BrowserTab] {
        let synced = records.compactMap { record -> BrowserSyncTab? in
            guard case .tab(let tab)? = record.payload, tab.spaceID == spaceID else { return nil }
            return tab
        }
        .filter { tab in
            tab.placement == .current ? preferences.currentTabs : preferences.savedStructure
        }
        .sorted { first, second in
            let firstPlacement = first.placement.sortIndex
            let secondPlacement = second.placement.sortIndex
            return firstPlacement == secondPlacement ? ordered(first, second) : firstPlacement < secondPlacement
        }

        var tabs = (local?.tabs ?? []).filter { tab in
            tab.placement == .current ? !preferences.currentTabs : !preferences.savedStructure
        }
        let localTabsByID = Dictionary(uniqueKeysWithValues: (local?.tabs ?? []).map { ($0.id, $0) })
        let syncedIDs = Set(synced.map(\.id))
        tabs.removeAll { syncedIDs.contains($0.id) }
        let folderIDs = Set(folders.map(\.id))

        for tab in synced {
            if tab.placement == .saved,
                let folderID = tab.folderID,
                !folderIDs.contains(folderID)
            {
                // A folder record that belongs to a different Space cannot be
                // explained by delivery order, so it stays fail-closed.
                guard (folderRecordSpaceIDs[folderID] ?? spaceID) == spaceID else {
                    throw BrowserSyncError.danglingFolder(tab.id)
                }
                // Otherwise the folder either has not arrived yet or somebody
                // deleted it. Holding the tab out of this session is what both
                // cases need, and it costs nothing: the record itself is
                // untouched, so `stage` keeps it while the folder is still on its
                // way and tombstones it once the folder is gone. Materializing it
                // instead would be worse than either — runtime repair strips a
                // folder it cannot find, and the next stage would upload that
                // stripped placement to every device.
                continue
            }
            tabs.append(
                BrowserTab(
                    id: tab.id,
                    title: tab.title,
                    url: tab.url,
                    savedURL: tab.placement == .current ? nil : tab.savedURL,
                    symbol: tab.symbol,
                    faviconData: localTabsByID[tab.id]?.faviconData,
                    faviconURL: localTabsByID[tab.id]?.faviconURL,
                    iconAccent: localTabsByID[tab.id]?.iconAccent,
                    iconMode: localTabsByID[tab.id]?.iconMode,
                    placement: tab.placement,
                    folderID: tab.placement == .saved ? tab.folderID : nil,
                    // Membership is carried through as written. A member whose
                    // siblings have not arrived yet is simply a smaller group,
                    // so there is nothing to hold back and nothing to wait for:
                    // repair keeps a lone member's ID and the group
                    // reconstitutes when the rest of the batch lands.
                    splitGroupID: tab.splitGroupID,
                    lastActivatedAt: tab.lastActivatedAt,
                    positionModifiedAt: tab.positionModifiedAt,
                    customTitle: tab.customTitle,
                    titleModifiedAt: tab.titleModifiedAt,
                    keepsPageLoaded: tab.keepsPageLoaded
                ))
        }
        if tabs.filter({ $0.placement == .pinned }).count > BrowserSpace.maximumPinnedTabs {
            throw BrowserSyncError.tooManyPinnedTabs(spaceID)
        }
        return tabs
    }

    private static func materializedArchive(
        spaceID: SpaceID,
        records: [BrowserSyncRecord],
        preferences: BrowserSyncPreferences,
        local: BrowserSpace?,
        activeTabs: [BrowserTab]
    ) -> [ArchivedTab] {
        guard preferences.historyAndArchive else { return local?.archivedTabs ?? [] }
        let activeTabIDs = Set(activeTabs.map(\.id))
        let localArchiveByID = Dictionary(
            uniqueKeysWithValues: (local?.archivedTabs ?? []).map { ($0.id, $0.tab) }
        )
        return records.compactMap { record -> BrowserSyncArchive? in
            guard case .archive(let archive)? = record.payload,
                archive.spaceID == spaceID,
                !activeTabIDs.contains(archive.id)
            else { return nil }
            return archive
        }
        .sorted { ordered($0.tab, $1.tab) }
        .map { archive in
            ArchivedTab(
                tab: BrowserTab(
                    id: archive.tab.id,
                    title: archive.tab.title,
                    url: archive.tab.url,
                    symbol: archive.tab.symbol,
                    faviconData: localArchiveByID[archive.tab.id]?.faviconData,
                    faviconURL: localArchiveByID[archive.tab.id]?.faviconURL,
                    iconAccent: localArchiveByID[archive.tab.id]?.iconAccent,
                    iconMode: localArchiveByID[archive.tab.id]?.iconMode,
                    placement: .current,
                    folderID: nil,
                    // No `splitGroupID`: an archived tab has left its split, and
                    // restoring it brings back a plain tab.
                    lastActivatedAt: archive.tab.lastActivatedAt,
                    positionModifiedAt: archive.tab.positionModifiedAt,
                    customTitle: archive.tab.customTitle,
                    titleModifiedAt: archive.tab.titleModifiedAt,
                    keepsPageLoaded: archive.tab.keepsPageLoaded
                ),
                archivedAt: archive.archivedAt,
                reason: archive.reason
            )
        }
    }

    private static func materializedHistory(
        spaceID: SpaceID,
        records: [BrowserSyncRecord],
        preferences: BrowserSyncPreferences,
        local: BrowserSpace?
    ) -> [BrowserHistoryEntry] {
        guard preferences.historyAndArchive else { return local?.history ?? [] }
        return records.compactMap { record -> BrowserSyncHistory? in
            guard case .history(let history)? = record.payload, history.spaceID == spaceID else { return nil }
            return history
        }
        .sorted { first, second in
            if first.lastVisitedAt != second.lastVisitedAt {
                return first.lastVisitedAt > second.lastVisitedAt
            }
            return first.id.uuidString < second.id.uuidString
        }
        .prefix(BrowserSession.maximumHistoryEntriesPerSpace)
        .map {
            BrowserHistoryEntry(
                id: $0.id,
                url: $0.url,
                title: $0.title,
                firstVisitedAt: $0.firstVisitedAt,
                lastVisitedAt: $0.lastVisitedAt,
                visitCount: $0.visitCount
            )
        }
    }

    private static func ordered(_ first: BrowserSyncSpace, _ second: BrowserSyncSpace) -> Bool {
        first.orderToken == second.orderToken
            ? first.id.rawValue.uuidString < second.id.rawValue.uuidString
            : first.orderToken < second.orderToken
    }

    private static func ordered(_ first: BrowserSyncFolder, _ second: BrowserSyncFolder) -> Bool {
        first.orderToken == second.orderToken
            ? first.id.rawValue.uuidString < second.id.rawValue.uuidString
            : first.orderToken < second.orderToken
    }

    private static func ordered(_ first: BrowserSyncTab, _ second: BrowserSyncTab) -> Bool {
        first.orderToken == second.orderToken
            ? first.id.rawValue.uuidString < second.id.rawValue.uuidString
            : first.orderToken < second.orderToken
    }
}
