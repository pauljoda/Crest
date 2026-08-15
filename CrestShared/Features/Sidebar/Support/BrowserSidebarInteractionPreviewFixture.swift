import Foundation

@MainActor
struct BrowserSidebarInteractionPreviewFixture {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let space: BrowserSpace
    let pinnedTabs: [BrowserTab]
    let pinnedTab: BrowserTab
    let savedTab: BrowserTab
    let currentTab: BrowserTab
    let folder: SavedFolder
    let siblingFolder: SavedFolder

    var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(space: space)
    }

    var tabAssignment: BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(
            tabID: savedTab.id,
            spaceID: space.id,
            profileID: space.profile.id
        )
    }

    var folderAssignment: BrowserFolderRuntimeAssignment {
        BrowserFolderRuntimeAssignment(
            folderID: folder.id,
            spaceID: space.id,
            profileID: space.profile.id
        )
    }

    var tabDropLocation: BrowserTabDropLocation {
        BrowserTabDropLocation(
            placement: .saved,
            folderID: folder.id,
            beforeTabID: savedTab.id,
            destinationAssignment: assignment
        )
    }

    var folderDropLocation: BrowserFolderDropLocation {
        BrowserFolderDropLocation(
            parentID: nil,
            beforeSiblingID: siblingFolder.id
        )
    }

    var spaceWithoutPinnedTabs: BrowserSpace {
        var result = space
        result.tabs.removeAll { $0.placement == .pinned }
        result.selectedTabID = currentTab.id
        return result
    }

    init() {
        let profileID = Self.uuid(0x11)
        let spaceID = SpaceID(rawValue: Self.uuid(0x21))
        let folder = SavedFolder(
            id: FolderID(rawValue: Self.uuid(0x41)),
            title: "Reading List",
            symbol: "books.vertical.fill",
            color: .ocean,
            isCollapsed: false
        )
        let nestedFolder = SavedFolder(
            id: FolderID(rawValue: Self.uuid(0x42)),
            title: "SwiftUI",
            symbol: "swift",
            color: .indigo,
            parentID: folder.id,
            isCollapsed: false
        )
        let siblingFolder = SavedFolder(
            id: FolderID(rawValue: Self.uuid(0x43)),
            title: "Archive",
            symbol: "archivebox.fill",
            color: .gold,
            isCollapsed: true
        )
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
        let savedTab = BrowserTab(
            id: TabID(rawValue: Self.uuid(0x33)),
            title: "SwiftUI Reference",
            url: Self.url("swiftui-reference/current"),
            savedURL: Self.url("swiftui-reference/saved"),
            symbol: "swift",
            faviconData: faviconData,
            iconAccent: BrowserTabIconAccent(
                red: 0.94,
                green: 0.44,
                blue: 0.20
            ),
            iconMode: .pulled,
            placement: .saved,
            folderID: folder.id,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_030)
        )
        let currentTab = BrowserTab(
            id: TabID(rawValue: Self.uuid(0x34)),
            title: "Release Notes",
            url: Self.url("release-notes"),
            symbol: "checkmark.seal.fill",
            faviconData: faviconData,
            iconAccent: BrowserTabIconAccent(
                red: 0.24,
                green: 0.72,
                blue: 0.55
            ),
            iconMode: .pulled,
            placement: .current,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_040)
        )
        let space = BrowserSpace(
            id: spaceID,
            profile: BrowsingProfile(id: profileID),
            name: "Product",
            symbol: "hammer.fill",
            accent: .indigo,
            folders: [folder, nestedFolder, siblingFolder],
            tabs: [firstPinnedTab, secondPinnedTab, savedTab, currentTab],
            selectedTabID: firstPinnedTab.id
        )
        let alternateSpace = BrowserSpace(
            id: SpaceID(rawValue: Self.uuid(0x22)),
            profile: BrowsingProfile(id: Self.uuid(0x12)),
            name: "Personal",
            symbol: "house.fill",
            accent: .orange,
            folders: [],
            tabs: [
                BrowserTab(
                    id: TabID(rawValue: Self.uuid(0x35)),
                    title: "Weekend Plans",
                    url: Self.url("weekend-plans"),
                    symbol: "sun.max.fill",
                    faviconData: faviconData,
                    iconMode: .pulled,
                    placement: .current,
                    lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_050)
                )
            ],
            selectedTabID: TabID(rawValue: Self.uuid(0x35))
        )
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [space, alternateSpace],
                selectedSpaceID: space.id
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault(),
            syncCoordinator: nil,
            browsingMode: .privateBrowsing
        )

        self.browser = browser
        spaceAccess = BrowserSpaceAccessController(
            authenticator: BrowserSidebarInteractionPreviewAuthenticator()
        )
        self.space = space
        pinnedTabs = [firstPinnedTab, secondPinnedTab]
        pinnedTab = firstPinnedTab
        self.savedTab = savedTab
        self.currentTab = currentTab
        self.folder = folder
        self.siblingFolder = siblingFolder
    }

    func makeTabDragState(
        tab: BrowserTab? = nil,
        placement: TabPlacement? = nil,
        dropLocation: BrowserTabDropLocation? = nil
    ) -> BrowserTabDragState {
        let tab = tab ?? pinnedTab
        let state = BrowserTabDragState()
        state.begin(
            item: BrowserTabDragItem(
                tabID: tab.id,
                spaceID: space.id,
                profileID: space.profile.id
            ),
            placement: placement ?? tab.placement
        )
        if let dropLocation {
            _ = state.enter(dropLocation)
        }
        return state
    }

    func makeFolderDragState(
        dropLocation: BrowserFolderDropLocation? = nil
    ) -> BrowserFolderDragState {
        let state = BrowserFolderDragState()
        state.begin(
            item: BrowserFolderDragItem(
                folderID: folder.id,
                spaceID: space.id,
                profileID: space.profile.id
            )
        )
        if let dropLocation {
            _ = state.enter(dropLocation)
        }
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
