import Foundation

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
