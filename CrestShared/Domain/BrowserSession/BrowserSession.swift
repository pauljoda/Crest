import Foundation

struct BrowserSession: Codable, Equatable, Sendable {
    var spaces: [BrowserSpace]
    var selectedSpaceID: SpaceID
    var defaultSpaceID: SpaceID? = nil
    var disposableSeedMarker: UUID? = nil
}

// MARK: - Factories

extension BrowserSession {
    static func makeBlankSpace(number: Int) -> BrowserSpace {
        let accent = SpaceAccent.allCases[(number - 1) % SpaceAccent.allCases.count]
        let tab = BrowserTab.startPage()
        return BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Space \(number)",
            symbol: "square.grid.2x2.fill",
            accent: accent,
            branding: .initial(accent: accent, symbol: "square.grid.2x2.fill"),
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
    }

    static var freshInstallSeed: BrowserSession {
        let tab = BrowserTab.startPage()
        let accent = SpaceAccent.indigo
        let symbol = "person.fill"
        // The very first Space a reader ever sees wears a shipped palette, so the
        // fresh install already looks like the swatch row it can be re-dressed
        // from. Winter is the quietest of the nine.
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Personal",
            symbol: symbol,
            accent: accent,
            branding: .house(.winter, symbol: symbol),
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        return BrowserSession(
            spaces: [space],
            selectedSpaceID: space.id,
            disposableSeedMarker: UUID()
        )
    }

    static func privateBrowsing() -> BrowserSession {
        let tab = BrowserTab.startPage()
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Private",
            symbol: BrowserPrivateBrowsingAppearance.symbol,
            accent: .indigo,
            branding: BrowserPrivateBrowsingAppearance.branding,
            folders: [],
            tabs: [tab],
            browsingPreferences: BrowserSpaceBrowsingPreferences(
                searchProvider: .duckDuckGo,
                currentTabCleanupPolicy: .never
            ),
            credentialPreferences: BrowserCredentialPreferences(
                isEnabled: false,
                syncsCrestPasswordsWithICloud: false,
                alsoOffersSaveToSystemPasswords: false
            ),
            selectedTabID: tab.id
        )
        return BrowserSession(spaces: [space], selectedSpaceID: space.id)
    }
}
// MARK: - Persistence

extension BrowserSession {
    var selectedSpaceIndex: Int? {
        spaces.firstIndex { $0.id == selectedSpaceID }
    }

    var selectedTabIndices: (space: Int, tab: Int)? {
        guard let spaceIndex = selectedSpaceIndex else { return nil }
        guard let tabID = spaces[spaceIndex].selectedTabID else { return nil }
        guard let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }) else { return nil }
        return (spaceIndex, tabIndex)
    }

    mutating func ensureSelection(in spaceID: SpaceID) {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        guard spaces[index].selectedTabID.map(spaces[index].contains) != true else { return }
        spaces[index].selectedTabID =
            spaces[index].currentTabs.first?.id
            ?? spaces[index].pinnedTabs.first?.id
            ?? spaces[index].savedTabs.first?.id
    }

}

// MARK: - Queries

extension BrowserSession {
    var hasDisposableSeedState: Bool {
        disposableSeedMarker != nil
    }

    var selectedSpace: BrowserSpace? {
        spaces.first { $0.id == selectedSpaceID }
    }

    var selectedTab: BrowserTab? {
        guard let space = selectedSpace, let selectedTabID = space.selectedTabID else { return nil }
        return space.tabs.first { $0.id == selectedTabID }
    }

    var tabIDs: [TabID] {
        spaces.flatMap { $0.tabs.map(\.id) }
    }

    var tabRuntimeAssignments: Set<BrowserTabRuntimeAssignment> {
        Set(
            spaces.flatMap { space in
                space.tabs.map { tab in
                    BrowserTabRuntimeAssignment(
                        tabID: tab.id,
                        spaceID: space.id,
                        profileID: space.profile.id
                    )
                }
            }
        )
    }

    func space(id: SpaceID) -> BrowserSpace? {
        spaces.first { $0.id == id }
    }

    func spaceID(containing tabID: TabID) -> SpaceID? {
        spaces.first(where: { $0.contains(tabID) })?.id
    }
}

// MARK: - Integrity

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
                // Metadata is keyed by the stable group ID and may legitimately
                // arrive before its tab records in a CloudKit batch. Integrity
                // repair normalizes duplicates but does not prune an orphan;
                // explicit user mutations own dissolution cleanup.
                splitGroups: BrowserSplitGroupMetadata.normalized(
                    source.splitGroups
                ),
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
