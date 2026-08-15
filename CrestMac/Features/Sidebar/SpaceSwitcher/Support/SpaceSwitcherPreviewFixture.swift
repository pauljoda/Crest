import Foundation

@MainActor
enum SpaceSwitcherPreviewFixture {
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    static let firstSpace = makeSpace(
        idByte: 0x71,
        profileByte: 0x72,
        tabByte: 0x73,
        name: "Work",
        symbol: "briefcase.fill",
        accent: .indigo
    )
    static let secondSpace = makeSpace(
        idByte: 0x74,
        profileByte: 0x75,
        tabByte: 0x76,
        name: "Home",
        symbol: "house.fill",
        accent: .orange
    )

    static func makeContext() -> (
        browser: BrowserStore,
        pages: BrowserPagePool,
        spaceAccess: BrowserSpaceAccessController
    ) {
        let session = BrowserSession(
            spaces: [firstSpace, secondSpace],
            selectedSpaceID: firstSpace.id
        )
        let browser = BrowserStore(
            session: session,
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
        let pages = BrowserPagePool(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true,
            extensionControllerPool: BrowserExtensionControllerPool(),
            permissionCenter: BrowserSitePermissionCenter()
        )
        return (
            browser,
            pages,
            BrowserSpaceAccessController(
                authenticator: SpaceSwitcherPreviewAuthenticator()
            )
        )
    }

    private static func makeSpace(
        idByte: UInt8,
        profileByte: UInt8,
        tabByte: UInt8,
        name: String,
        symbol: String,
        accent: SpaceAccent
    ) -> BrowserSpace {
        let tabID = TabID(rawValue: uuid(tabByte))
        return BrowserSpace(
            id: SpaceID(rawValue: uuid(idByte)),
            profile: BrowsingProfile(id: uuid(profileByte)),
            name: name,
            symbol: symbol,
            accent: accent,
            branding: .initial(accent: accent, symbol: symbol),
            folders: [],
            tabs: [
                BrowserTab.startPage(
                    id: tabID,
                    lastActivatedAt: fixedDate
                )
            ],
            selectedTabID: tabID
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x53,
                0x57, 0x49,
                0x54, 0x43,
                0x48, 0x45, 0x52, 0x50, 0x52, finalByte
            ))
    }
}
