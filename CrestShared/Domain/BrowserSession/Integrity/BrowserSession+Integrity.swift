import Foundation

extension BrowserSession {
    /// Repairs persisted or conflict-merged state before any WebKit page is created.
    /// Tab IDs are process-wide page-pool keys and profile IDs are website-data-store
    /// keys, so duplicates across Spaces are an isolation failure rather than a cosmetic
    /// data issue. First occurrences retain their stable identity; later collisions are
    /// reidentified without copying website data.
    mutating func repairRuntimeIntegrity() {
        if spaces.isEmpty {
            let space = Self.makeBlankSpace(number: 1)
            spaces = [space]
            selectedSpaceID = space.id
            return
        }

        var seenSpaceIDs: Set<SpaceID> = []
        var seenProfileIDs: Set<UUID> = []
        var seenTabIDs: Set<TabID> = []

        for spaceIndex in spaces.indices {
            let source = spaces[spaceIndex]

            var repairedSpaceID = source.id
            if !seenSpaceIDs.insert(repairedSpaceID).inserted {
                repeat { repairedSpaceID = SpaceID() } while !seenSpaceIDs.insert(repairedSpaceID).inserted
            }

            var repairedProfile = source.profile
            if !seenProfileIDs.insert(repairedProfile.id).inserted {
                repeat { repairedProfile = BrowsingProfile() } while !seenProfileIDs.insert(repairedProfile.id).inserted
            }

            var validFolderIDs: Set<FolderID> = []
            let uniquelyIdentifiedFolders = source.folders.map { folder in
                guard validFolderIDs.insert(folder.id).inserted else {
                    var replacement = SavedFolder(
                        title: folder.title,
                        symbol: folder.symbol,
                        color: folder.color,
                        parentID: folder.parentID,
                        isCollapsed: folder.isCollapsed,
                        collapseModifiedAt: folder.collapseModifiedAt
                    )
                    while !validFolderIDs.insert(replacement.id).inserted {
                        replacement = SavedFolder(
                            title: folder.title,
                            symbol: folder.symbol,
                            color: folder.color,
                            parentID: folder.parentID,
                            isCollapsed: folder.isCollapsed,
                            collapseModifiedAt: folder.collapseModifiedAt
                        )
                    }
                    return replacement
                }
                return folder
            }
            let repairedFolders = BrowserFolderTree.repairedPreorder(
                uniquelyIdentifiedFolders
            )
            validFolderIDs = Set(repairedFolders.map(\.id))

            var repairedSelectedTabID: TabID?
            var pinnedCount = 0
            var repairedTabs = source.tabs.map { tab in
                var repairedID = tab.id
                if !seenTabIDs.insert(repairedID).inserted {
                    repeat { repairedID = TabID() } while !seenTabIDs.insert(repairedID).inserted
                }

                var placement = tab.placement
                if placement == .pinned {
                    pinnedCount += 1
                    if pinnedCount > BrowserSpace.maximumPinnedTabs {
                        placement = .saved
                    }
                }
                let repairedFolderID =
                    placement == .saved
                        && tab.folderID.map(validFolderIDs.contains) == true
                    ? tab.folderID
                    : nil
                let isStartPage = tab.url == nil
                let repairedTab = BrowserTab(
                    id: repairedID,
                    title: isStartPage ? BrowserTab.startPageTitle : tab.title,
                    url: tab.url,
                    savedURL: placement == .current ? nil : tab.savedSiteURL,
                    symbol: isStartPage ? BrowserTab.startPageSymbol : tab.symbol,
                    faviconData: tab.faviconData,
                    faviconURL: tab.faviconURL,
                    iconAccent: tab.iconAccent,
                    iconMode: tab.iconMode,
                    placement: placement,
                    folderID: repairedFolderID,
                    splitGroupID: tab.splitGroupID,
                    lastActivatedAt: tab.lastActivatedAt,
                    positionModifiedAt: tab.positionModifiedAt,
                    customTitle: tab.customTitle,
                    titleModifiedAt: tab.titleModifiedAt,
                    keepsPageLoaded: tab.keepsPageLoaded
                )
                if repairedSelectedTabID == nil, source.selectedTabID == tab.id {
                    repairedSelectedTabID = repairedTab.id
                }
                return repairedTab
            }

            if repairedTabs.isEmpty {
                var replacement = BrowserTab.startPage()
                while !seenTabIDs.insert(replacement.id).inserted {
                    replacement = BrowserTab.startPage()
                }
                repairedTabs = [replacement]
                repairedSelectedTabID = replacement.id
            }
            // Split membership is repaired, never reordered, and never
            // dissolved down to nothing: a lone member of a group whose
            // siblings have not been merged in yet keeps its ID so the group
            // reconstitutes instead of being stripped and re-uploaded.
            repairedTabs = BrowserSplitGroupNormalizer.normalized(repairedTabs)

            let repairedArchive: [ArchivedTab] = source.archivedTabs.compactMap { archived in
                guard !archived.tab.isStartPage else { return nil }
                var repairedID = archived.tab.id
                if !seenTabIDs.insert(repairedID).inserted {
                    repeat { repairedID = TabID() } while !seenTabIDs.insert(repairedID).inserted
                }
                let repairedTab = BrowserTab(
                    id: repairedID,
                    title: archived.tab.title,
                    url: archived.tab.url,
                    savedURL: nil,
                    symbol: archived.tab.symbol,
                    faviconData: nil,
                    faviconURL: archived.tab.faviconURL,
                    iconAccent: archived.tab.iconAccent,
                    iconMode: archived.tab.iconMode,
                    placement: .current,
                    folderID: nil,
                    // No `splitGroupID`: archiving a tab takes it out of its
                    // split, and a restored tab comes back as a plain tab.
                    lastActivatedAt: archived.tab.lastActivatedAt,
                    positionModifiedAt: archived.tab.positionModifiedAt,
                    customTitle: archived.tab.customTitle,
                    titleModifiedAt: archived.tab.titleModifiedAt,
                    keepsPageLoaded: archived.tab.keepsPageLoaded
                )
                return ArchivedTab(
                    tab: repairedTab,
                    archivedAt: archived.archivedAt,
                    reason: archived.reason
                )
            }

            spaces[spaceIndex] = BrowserSpace(
                id: repairedSpaceID,
                profile: repairedProfile,
                name: source.name,
                symbol: source.symbol,
                accent: source.accent,
                branding: source.branding,
                folders: repairedFolders,
                tabs: repairedTabs,
                archivedTabs: repairedArchive,
                history: Array(source.history.prefix(Self.maximumHistoryEntriesPerSpace)),
                browsingPreferences: source.browsingPreferences,
                credentialPreferences: source.credentialPreferences,
                accessPolicy: source.accessPolicy,
                isSavedTabsExpanded: source.isSavedTabsExpanded,
                savedTabsExpansionModifiedAt: source
                    .savedTabsExpansionModifiedAt,
                selectedTabID: repairedSelectedTabID
            )
            ensureSelection(in: repairedSpaceID)
        }

        if !spaces.contains(where: { $0.id == selectedSpaceID }) {
            selectedSpaceID = spaces[0].id
        }
        if defaultSpaceID.map({ id in spaces.contains { $0.id == id } }) != true {
            defaultSpaceID = selectedSpaceID
        }
        ensureSelection(in: selectedSpaceID)
    }

}
