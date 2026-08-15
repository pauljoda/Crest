import Foundation

@MainActor
enum BrowserDataPortabilityPreviewFixture {
    static let previewDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func makeModel(
        isProtected: Bool = false
    ) -> BrowserDataPortabilityModel {
        let space = BrowserSpace(
            id: SpaceID(
                rawValue: UUID(
                    uuid: (
                        0x44, 0x41, 0x54, 0x41, 0x50, 0x4F, 0x52, 0x54,
                        0x41, 0x42, 0x49, 0x4C, 0x49, 0x54, 0x59, 0x01
                    )
                )
            ),
            profile: BrowsingProfile(
                id: UUID(
                    uuid: (
                        0x44, 0x41, 0x54, 0x41, 0x50, 0x4F, 0x52, 0x54,
                        0x41, 0x42, 0x49, 0x4C, 0x49, 0x54, 0x59, 0x02
                    )
                )
            ),
            name: isProtected ? "Private Research" : "Research",
            symbol: isProtected ? "lock.shield.fill" : "books.vertical.fill",
            accent: .indigo,
            folders: [],
            tabs: [
                BrowserTab(
                    id: TabID(
                        rawValue: UUID(
                            uuid: (
                                0x44, 0x41, 0x54, 0x41, 0x50, 0x4F, 0x52, 0x54,
                                0x41, 0x42, 0x49, 0x4C, 0x49, 0x54, 0x59, 0x03
                            )
                        )
                    ),
                    title: "Reference",
                    url: URL(string: "https://example.com/reference"),
                    symbol: "doc.text.fill",
                    placement: .saved,
                    lastActivatedAt: previewDate
                )
            ],
            accessPolicy: isProtected ? .deviceOwnerAuthentication : .open,
            selectedTabID: nil
        )
        let session = BrowserSession(
            spaces: [space],
            selectedSpaceID: space.id
        )
        let browser = BrowserStore(
            session: session,
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
        let accessController = BrowserSpaceAccessController(
            authenticator: BrowserDataPortabilityPreviewAuthenticator()
        )
        return BrowserDataPortabilityModel(
            browser: browser,
            spaceAccess: accessController,
            operations: BrowserDataPortabilityPreviewOperations()
        )
    }
}
