import Foundation

@MainActor
enum BrowserDetailPreviewFixture {
    static let spaceID = SpaceID(rawValue: uuid(0x31))
    static let profileID = uuid(0x32)
    static let tabID = TabID(rawValue: uuid(0x33))
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    static let space = BrowserSpace(
        id: spaceID,
        profile: BrowsingProfile(id: profileID),
        name: "Research",
        symbol: "books.vertical.fill",
        accent: .indigo,
        branding: .initial(
            accent: .indigo,
            symbol: "books.vertical.fill"
        ),
        folders: [],
        tabs: [
            BrowserTab.startPage(
                id: tabID,
                lastActivatedAt: fixedDate
            )
        ],
        selectedTabID: tabID
    )

    static func makeBrowser() -> BrowserStore {
        BrowserStore(
            session: BrowserSession(
                spaces: [space],
                selectedSpaceID: spaceID
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault()
        )
    }

    static func makeWebContent() -> (
        browser: BrowserStore,
        pages: BrowserPagePool,
        page: BrowserPage
    ) {
        let browser = makeBrowser()
        let pages = BrowserPagePool(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )
        guard let tab = space.tabs.first(where: { $0.id == tabID }) else {
            preconditionFailure("The fixed detail preview tab is missing.")
        }
        pages.select(tab: tab, space: space, at: fixedDate)
        guard
            let page = pages.activePage,
            page.spaceID == spaceID,
            page.profileID == profileID
        else {
            preconditionFailure(
                "The detail preview page must retain its fixed Space assignment."
            )
        }
        return (browser, pages, page)
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x44,
                0x45, 0x54,
                0x41, 0x49,
                0x4C, 0x50, 0x52, 0x45, 0x56, finalByte
            ))
    }
}
