import Foundation

@MainActor
struct BrowserLinkSettingsPreviewFixture {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let links: BrowserLinkPreferenceStore
    let primarySpace: BrowserSpace
    let secondarySpace: BrowserSpace
    let route: BrowserLinkRoute

    init() {
        let primarySpace = BrowserSpace(
            id: SpaceID(rawValue: Self.uuid(0x21)),
            profile: BrowsingProfile(id: Self.uuid(0x31)),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: [],
            selectedTabID: nil
        )
        let secondarySpace = BrowserSpace(
            id: SpaceID(rawValue: Self.uuid(0x22)),
            profile: BrowsingProfile(id: Self.uuid(0x32)),
            name: "Personal",
            symbol: "house.fill",
            accent: .orange,
            folders: [],
            tabs: [],
            selectedTabID: nil
        )
        let route = BrowserLinkRoute(
            id: Self.uuid(0x41),
            match: .contains,
            pattern: "developer.apple.com",
            destinationSpaceID: primarySpace.id
        )
        var preferences = BrowserLinkPreferences.default
        preferences.externalLinkDestination = .chosenSpace
        preferences.externalLinkSpaceID = secondarySpace.id
        preferences.peekClickModifier = .command
        preferences.quickWindowArchivePolicy = .after1Hour
        preferences.routes = [route]

        browser = BrowserStore(
            session: BrowserSession(
                spaces: [primarySpace, secondarySpace],
                selectedSpaceID: primarySpace.id
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault(),
            syncCoordinator: nil,
            browsingMode: .privateBrowsing
        )
        spaceAccess = BrowserSpaceAccessController(
            authenticator: BrowserLinkSettingsPreviewAuthenticator()
        )
        links = BrowserLinkPreferenceStore(
            persistence: InMemoryBrowserLinkPreferencesPersistence(
                preferences: preferences
            )
        )
        self.primarySpace = primarySpace
        self.secondarySpace = secondarySpace
        self.route = route
    }

    private static func uuid(_ tail: UInt8) -> UUID {
        UUID(
            uuid: (
                0, 0, 0, 0, 0, 0, 0x40, 0,
                0x80, 0, 0, 0, 0, 0, 0, tail
            )
        )
    }
}
