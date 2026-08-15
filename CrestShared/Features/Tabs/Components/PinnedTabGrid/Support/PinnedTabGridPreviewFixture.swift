import Foundation

@MainActor
struct PinnedTabGridPreviewFixture {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let space: BrowserSpace
    let pinnedTabs: [BrowserTab]
    let pinnedTab: BrowserTab

    var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(space: space)
    }

    init() {
        let faviconData = Self.inlineFaviconData
        let firstPinnedTab = BrowserTab(
            id: TabID(rawValue: Self.uuid(0x31)),
            title: "Crest Architecture",
            url: Self.url("architecture"),
            symbol: "square.grid.2x2.fill",
            faviconData: faviconData,
            iconAccent: BrowserTabIconAccent(
                red: 0.31,
                green: 0.58,
                blue: 0.96
            ),
            iconMode: .pulled,
            placement: .pinned,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_010)
        )
        let secondPinnedTab = BrowserTab(
            id: TabID(rawValue: Self.uuid(0x32)),
            title: "Design System",
            url: Self.url("design-system"),
            symbol: "paintpalette.fill",
            faviconData: faviconData,
            iconAccent: BrowserTabIconAccent(
                red: 0.82,
                green: 0.35,
                blue: 0.48
            ),
            iconMode: .pulled,
            placement: .pinned,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_020)
        )
        let space = BrowserSpace(
            id: SpaceID(rawValue: Self.uuid(0x21)),
            profile: BrowsingProfile(id: Self.uuid(0x11)),
            name: "Product",
            symbol: "hammer.fill",
            accent: .indigo,
            folders: [],
            tabs: [firstPinnedTab, secondPinnedTab],
            selectedTabID: firstPinnedTab.id
        )
        let alternateTab = BrowserTab.startPage(
            id: TabID(rawValue: Self.uuid(0x35)),
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_030)
        )
        let alternateSpace = BrowserSpace(
            id: SpaceID(rawValue: Self.uuid(0x22)),
            profile: BrowsingProfile(id: Self.uuid(0x12)),
            name: "Personal",
            symbol: "house.fill",
            accent: .orange,
            folders: [],
            tabs: [alternateTab],
            selectedTabID: alternateTab.id
        )

        browser = BrowserStore(
            session: BrowserSession(
                spaces: [space, alternateSpace],
                selectedSpaceID: space.id
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault(),
            syncCoordinator: nil,
            browsingMode: .privateBrowsing
        )
        spaceAccess = BrowserSpaceAccessController(
            authenticator: PinnedTabGridPreviewAuthenticator()
        )
        self.space = space
        pinnedTabs = [firstPinnedTab, secondPinnedTab]
        pinnedTab = firstPinnedTab
    }

    func makeTabDragState() -> BrowserTabDragState {
        let state = BrowserTabDragState()
        state.begin(
            item: BrowserTabDragItem(
                tabID: pinnedTab.id,
                spaceID: space.id,
                profileID: space.profile.id
            ),
            placement: pinnedTab.placement
        )
        return state
    }

    private static func uuid(_ tail: UInt8) -> UUID {
        UUID(
            uuid: (
                0, 0, 0, 0, 0, 0, 0x40, 0,
                0x80, 0, 0, 0, 0, 0, 0, tail
            )
        )
    }

    private static func url(_ path: String) -> URL {
        guard let url = URL(string: "crest-preview://pinned-tabs/\(path)") else {
            preconditionFailure("Pinned Tab Grid preview URL is invalid")
        }
        return url
    }

    private static let inlineFaviconData = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
        0x54, 0x08, 0xD7, 0x63, 0x60, 0x68, 0xF8, 0xCF,
        0xF0, 0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89,
        0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ])
}
