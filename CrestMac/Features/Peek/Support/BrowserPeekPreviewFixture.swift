import Foundation

@MainActor
enum BrowserPeekPreviewFixture {
    static let space = BrowserSpace(
        id: SpaceID(rawValue: uuid(0x11)),
        profile: BrowsingProfile(id: uuid(0x21)),
        name: "Research",
        symbol: "books.vertical.fill",
        accent: .indigo,
        folders: [],
        tabs: [tab],
        accessPolicy: .deviceOwnerAuthentication,
        selectedTabID: tab.id
    )
    static let request = BrowserPeekRequest(
        id: uuid(0x41),
        url: URL(string: "about:blank") ?? URL(fileURLWithPath: "/"),
        sourceTabID: tab.id,
        sourceTitle: "Research",
        spaceAssignment: BrowserSpaceRuntimeAssignment(space: space),
        trigger: .modifierClick,
        sourcePresentation: BrowserPeekSourcePresentation(
            normalizedMinX: 0.18,
            normalizedMinY: 0.22,
            normalizedWidth: 0.2,
            normalizedHeight: 0.08,
            normalizedTouchX: 0.28,
            normalizedTouchY: 0.3,
            label: "Research link"
        )
    )

    static func makeBrowser() -> BrowserStore {
        BrowserStore(
            session: BrowserSession(
                spaces: [space],
                selectedSpaceID: space.id
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault(),
            browsingMode: .privateBrowsing
        )
    }

    static func makeAccessController() -> BrowserSpaceAccessController {
        BrowserSpaceAccessController(
            authenticator: BrowserPeekPreviewAuthenticator()
        )
    }

    static func makeModel() -> BrowserPeekModel {
        let coordinator = BrowserTransientBrowsingCoordinator()
        coordinator.presentPeek(request)
        return BrowserPeekModel(
            previewing: request,
            browser: makeBrowser(),
            spaceAccess: makeAccessController(),
            coordinator: coordinator
        )
    }

    private static let tab = BrowserTab.startPage(
        id: TabID(rawValue: uuid(0x31)),
        lastActivatedAt: Date(timeIntervalSince1970: 0)
    )

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x50,
                0x45, 0x45,
                0x4B, 0x50,
                0x52, 0x45, 0x56, 0x49, 0x45, finalByte
            ))
    }
}
