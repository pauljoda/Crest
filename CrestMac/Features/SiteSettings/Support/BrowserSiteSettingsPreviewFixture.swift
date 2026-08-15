import Foundation

@MainActor
enum BrowserSiteSettingsPreviewFixture {
    static let spaceID = SpaceID(rawValue: uuid(0x51))
    static let profileID = uuid(0x52)
    static let tabID = TabID(rawValue: uuid(0x53))
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    static let pageURL: URL = {
        guard let url = URL(string: "https://example.com") else {
            preconditionFailure("The Site Settings preview URL is invalid.")
        }
        return url
    }()
    static let origin = BrowserSiteOrigin(
        scheme: "https",
        host: "example.com",
        port: 443
    )

    static func makePage() -> (
        page: BrowserPage,
        permissionCenter: BrowserSitePermissionCenter
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
        let permissionCenter = BrowserSitePermissionCenter()
        let pages = BrowserPagePool(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true,
            permissionCenter: permissionCenter
        )
        pages.select(tab: tab, space: space, at: fixedDate)
        guard let page = pages.activePage else {
            preconditionFailure("The Site Settings preview page is missing.")
        }
        return (page, permissionCenter)
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x53,
                0x49, 0x54,
                0x45, 0x53,
                0x45, 0x54, 0x54, 0x49, 0x4E, finalByte
            ))
    }
}
