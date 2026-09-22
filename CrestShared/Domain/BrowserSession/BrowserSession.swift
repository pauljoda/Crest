import Foundation

struct BrowserSession: Codable, Equatable, Sendable {
    var spaces: [BrowserSpace]
    var selectedSpaceID: SpaceID
    var defaultSpaceID: SpaceID? = nil
    var disposableSeedMarker: UUID? = nil
    /// Local cleanup work. These intents never become CloudKit records.
    var spaceDeletions: [BrowserSpaceDeletionIntent]? = nil
}

struct BrowserSpaceDeletionIntent: Codable, Equatable, Sendable {
    let spaceID: SpaceID
    let profileID: UUID
    let operationID: UUID
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
        guard spaceDeletions?.contains(where: { $0.spaceID == selectedSpaceID }) != true else { return nil }
        return spaces.first { $0.id == selectedSpaceID }
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
        // No page or startup save may use an unaccepted repair. Operational
        // sync errors use the throwing bridge before the coordinator commits.
        do { self = try BrowserCoreSync.repair(self) }
        catch { preconditionFailure("Core session repair failed before publication: \(error)") }
    }

}
