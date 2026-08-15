import Foundation

@MainActor
struct MobileBrowserSidebarPreviewFixture {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let space: BrowserSpace
    let protectedSpace: BrowserSpace
    let folder: SavedFolder
    let pinnedTab: BrowserTab
    let savedTab: BrowserTab
    let unfiledSavedTab: BrowserTab
    let currentTab: BrowserTab

    init() {
        let folder = SavedFolder(
            id: FolderID(rawValue: Self.uuid(0x21)),
            title: "Reading",
            color: .ocean,
            isCollapsed: false,
            collapseModifiedAt: Self.epoch
        )
        let pinnedTab = Self.tab(
            id: 0x31,
            title: "Crest Guide",
            path: "/CrestPreview/guide.html",
            emoji: "🧭",
            placement: .pinned
        )
        let savedTab = Self.tab(
            id: 0x32,
            title: "Design Notes",
            path: "/CrestPreview/design.html",
            emoji: "🎨",
            placement: .saved,
            folderID: folder.id
        )
        let unfiledSavedTab = Self.tab(
            id: 0x33,
            title: "SwiftUI Reference",
            path: "/CrestPreview/swiftui.html",
            emoji: "📚",
            placement: .saved
        )
        let currentTab = BrowserTab.startPage(
            id: TabID(rawValue: Self.uuid(0x34)),
            placement: .current,
            lastActivatedAt: Self.epoch
        )
        let space = BrowserSpace(
            id: SpaceID(rawValue: Self.uuid(0x11)),
            profile: BrowsingProfile(id: Self.uuid(0x12)),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [folder],
            tabs: [pinnedTab, savedTab, unfiledSavedTab, currentTab],
            history: [
                BrowserHistoryEntry(
                    id: Self.uuid(0x41),
                    url: URL(filePath: "/CrestPreview/history.html"),
                    title: "Crest History",
                    firstVisitedAt: Self.epoch,
                    lastVisitedAt: Self.epoch,
                    visitCount: 2
                )
            ],
            selectedTabID: currentTab.id
        )
        let protectedSpace = BrowserSpace(
            id: SpaceID(rawValue: Self.uuid(0x13)),
            profile: BrowsingProfile(id: Self.uuid(0x14)),
            name: "Personal",
            symbol: "lock.fill",
            accent: .orange,
            folders: [],
            tabs: [],
            accessPolicy: .deviceOwnerAuthentication,
            selectedTabID: nil
        )
        let base = MobileBrowserPreviewFixture()

        self.folder = folder
        self.pinnedTab = pinnedTab
        self.savedTab = savedTab
        self.unfiledSavedTab = unfiledSavedTab
        self.currentTab = currentTab
        self.space = space
        self.protectedSpace = protectedSpace
        browser = BrowserStore(
            session: BrowserSession(
                spaces: [space, protectedSpace],
                selectedSpaceID: space.id
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault(),
            browsingMode: .privateBrowsing
        )
        pages = base.pages
        spaceAccess = BrowserSpaceAccessController(
            authenticator: MobileBrowserPreviewAuthenticator()
        )
    }

    var folderNode: BrowserFolderNode {
        BrowserFolderNode(folder: folder, depth: 0, hasChildren: false)
    }

    private static let epoch = Date(timeIntervalSince1970: 0)

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x50, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, finalByte
            )
        )
    }

    private static func tab(
        id: UInt8,
        title: String,
        path: String,
        emoji: String,
        placement: TabPlacement,
        folderID: FolderID? = nil
    ) -> BrowserTab {
        BrowserTab(
            id: TabID(rawValue: uuid(id)),
            title: title,
            url: URL(filePath: path),
            symbol: BrowserTab.symbol(forEmoji: emoji),
            placement: placement,
            folderID: folderID,
            lastActivatedAt: epoch,
            positionModifiedAt: epoch
        )
    }
}
