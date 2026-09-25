import Foundation

/// The browsing data the core owns, as the native read projection. Which Space
/// and tab a window shows is the core device's window state, never part of the
/// session.
struct BrowserSession: Codable, Equatable, Sendable {
    var spaces: [BrowserSpace]
    var defaultSpaceID: SpaceID? = nil
    var disposableSeedMarker: UUID? = nil
    /// Local cleanup work. These intents never become CloudKit records.
    var spaceDeletions: [BrowserSpaceDeletionIntent]? = nil
    /// The core's device-local behavior preferences. Nil until the legacy
    /// settings are imported; only `preferences.*` commands change it.
    var appPreferences: BrowserAppPreferences? = nil

    /// The history the core keeps per Space.
    static var maximumHistoryEntriesPerSpace: Int { BrowserCoreLimits.current.historyEntries }
}

struct BrowserSpaceDeletionIntent: Equatable, Sendable {
    let spaceID: SpaceID
    let profileID: UUID
    let operationID: UUID
}

extension BrowserSpaceDeletionIntent: Codable {
    private enum CodingKeys: String, CodingKey {
        case spaceID
        case profileID
        case operationID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            spaceID: try container.decodeIdentity(forKey: .spaceID),
            profileID: try container.decode(UUID.self, forKey: .profileID),
            operationID: try container.decode(UUID.self, forKey: .operationID))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeStoredIdentity(spaceID, forKey: .spaceID)
        try container.encode(profileID, forKey: .profileID)
        try container.encode(operationID, forKey: .operationID)
    }
}

// MARK: - Factories

extension BrowserSession {
    static func makeBlankSpace(number: Int) -> BrowserSpace {
        let accent = SpaceAccent.all[(number - 1) % SpaceAccent.all.count]
        let tab = BrowserTab.startPage()
        return BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Space \(number)",
            symbol: "square.grid.2x2.fill",
            accent: accent,
            branding: .initial(accent: accent, symbol: "square.grid.2x2.fill"),
            folders: [],
            tabs: [tab]
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
            tabs: [tab]
        )
        return BrowserSession(
            spaces: [space],
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
            )
        )
        return BrowserSession(spaces: [space])
    }
}

// MARK: - Queries

extension BrowserSession {
    var hasDisposableSeedState: Bool {
        disposableSeedMarker != nil
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
