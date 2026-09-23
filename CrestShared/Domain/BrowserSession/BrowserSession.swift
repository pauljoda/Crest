import Foundation

struct BrowserSession: Codable, Equatable, Sendable {
    var spaces: [BrowserSpace]
    var selectedSpaceID: SpaceID
    var defaultSpaceID: SpaceID? = nil
    var disposableSeedMarker: UUID? = nil
    /// Local cleanup work. These intents never become CloudKit records.
    var spaceDeletions: [BrowserSpaceDeletionIntent]? = nil
    /// The core's device-local behavior preferences. Nil until the legacy
    /// settings are imported; only `preferences.*` commands change it.
    var appPreferences: BrowserAppPreferences? = nil
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

    /// Gives a Space whose selection is gone the core's fallback tab. The first
    /// tab of each placement are the only candidates the rule can choose
    /// between. When the core cannot answer, the selection is left as it was.
    mutating func ensureSelection(in spaceID: SpaceID) {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        guard spaces[index].selectedTabID.map(spaces[index].contains) != true else { return }
        let tabs = spaces[index].tabs
        let candidates = [TabPlacement.current, .pinned, .saved]
            .compactMap { placement in tabs.firstIndex { $0.placement == placement } }
            .sorted()
        guard !candidates.isEmpty else {
            spaces[index].selectedTabID = nil
            return
        }
        guard let chosen = BrowserCorePolicy.selectionFallback(placements: candidates.map { tabs[$0].placement })
        else { return }
        spaces[index].selectedTabID = tabs[candidates[chosen]].id
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
