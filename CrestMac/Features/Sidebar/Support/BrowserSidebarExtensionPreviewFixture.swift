import Foundation

@MainActor
enum BrowserSidebarExtensionPreviewFixture {
    static let spaceID = SpaceID(rawValue: uuid(0x61))
    static let profileID = uuid(0x62)
    static let tabID = TabID(rawValue: uuid(0x63))
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    static let pageURL: URL = {
        guard let url = URL(string: "https://example.com") else {
            preconditionFailure("The Sidebar preview URL is invalid.")
        }
        return url
    }()
    static let actions = [
        BrowserExtensionActionPresentation(
            id: "preview.notes",
            displayName: "Save to Notes",
            badgeText: "3",
            isPinned: true
        ),
        BrowserExtensionActionPresentation(
            id: "preview.reader",
            displayName: "Reader Tools",
            isPinned: true
        ),
        BrowserExtensionActionPresentation(
            id: "preview.disabled",
            displayName: "Unavailable Action",
            isEnabled: false
        ),
    ]

    static func makeContext() -> (
        browser: BrowserStore,
        pages: BrowserPagePool,
        configuration: BrowserSiteControlConfiguration
    ) {
        let tab = BrowserTab(
            id: tabID,
            title: "Example",
            url: pageURL,
            symbol: "globe",
            placement: .current,
            lastActivatedAt: fixedDate
        )
        let space = BrowserSpace(
            id: spaceID,
            profile: BrowsingProfile(id: profileID),
            name: "Preview",
            symbol: "globe",
            accent: .teal,
            branding: .initial(accent: .teal, symbol: "globe"),
            folders: [],
            tabs: [tab],
            selectedTabID: tabID
        )
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [space],
                selectedSpaceID: spaceID
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
        let extensionControllerPool = BrowserExtensionControllerPool()
        let permissionCenter = BrowserSitePermissionCenter()
        let pages = BrowserPagePool(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true,
            extensionControllerPool: extensionControllerPool,
            permissionCenter: permissionCenter
        )
        pages.select(tab: tab, space: space, at: fixedDate)
        guard let page = pages.activePage else {
            preconditionFailure("The Sidebar preview page is missing.")
        }
        return (
            browser,
            pages,
            BrowserSiteControlConfiguration(
                page: page,
                space: space,
                selectedTabID: tabID,
                extensionControllerPool: extensionControllerPool,
                permissionCenter: permissionCenter,
                manageExtensions: {}
            )
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x53,
                0x49, 0x44,
                0x45, 0x45,
                0x58, 0x54, 0x50, 0x52, 0x45, finalByte
            ))
    }
}
