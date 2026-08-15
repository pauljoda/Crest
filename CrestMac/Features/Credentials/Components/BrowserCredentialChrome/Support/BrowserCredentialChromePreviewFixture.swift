import Foundation

@MainActor
enum BrowserCredentialChromePreviewFixture {
    static let currentCredentialRequest = BrowserCredentialFillRequest(
        id: uuid(0x41),
        origin: credentialOrigin,
        topLevelOrigin: credentialOrigin,
        usernameHint: "reader@example.com",
        passwordKind: .current,
        isCrossOriginFrame: false,
        requestedAt: fixedDate
    )

    static let newCredentialRequest = BrowserCredentialFillRequest(
        id: uuid(0x42),
        origin: credentialOrigin,
        topLevelOrigin: credentialOrigin,
        usernameHint: "reader@example.com",
        passwordKind: .new,
        isCrossOriginFrame: false,
        requestedAt: fixedDate
    )

    static let credentialSaveCandidate = BrowserCredentialSaveCandidate(
        id: uuid(0x43),
        origin: credentialOrigin,
        topLevelOrigin: credentialOrigin,
        username: "reader@example.com",
        password: "preview-password",
        passwordKind: .current,
        isCrossOriginFrame: false,
        submittedAt: fixedDate
    )

    static func makeWebContent() -> (
        browser: BrowserStore,
        page: BrowserPage
    ) {
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [space],
                selectedSpaceID: spaceID
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault()
        )
        let pages = BrowserPagePool(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )
        guard let tab = space.tabs.first(where: { $0.id == tabID }) else {
            preconditionFailure("The fixed credential preview tab is missing.")
        }
        pages.select(tab: tab, space: space, at: fixedDate)
        guard
            let page = pages.activePage,
            page.spaceID == spaceID,
            page.profileID == profileID
        else {
            preconditionFailure(
                "The credential preview page must retain its fixed Space assignment."
            )
        }
        return (browser, page)
    }

    private static let spaceID = SpaceID(rawValue: uuid(0x51))
    private static let profileID = uuid(0x52)
    private static let tabID = TabID(rawValue: uuid(0x53))
    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static let space = BrowserSpace(
        id: spaceID,
        profile: BrowsingProfile(id: profileID),
        name: "Passwords",
        symbol: "key.fill",
        accent: .teal,
        branding: .initial(
            accent: .teal,
            symbol: "key.fill"
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

    private static let credentialOrigin: CredentialOrigin = {
        guard
            let url = URL(string: "https://accounts.preview.example"),
            let origin = CredentialOrigin(url: url)
        else {
            preconditionFailure("The fixed credential preview origin is invalid.")
        }
        return origin
    }()

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x43,
                0x52, 0x45,
                0x44, 0x45,
                0x4E, 0x54, 0x49, 0x41, 0x4C, finalByte
            ))
    }
}
