import Foundation

enum BrowserSidebarPreviewFixture {
    static let folderID = FolderID(rawValue: uuid(0x31))
    static let spaceID = SpaceID(rawValue: uuid(0x21))
    static let space = BrowserSpace(
        id: spaceID,
        profile: BrowsingProfile(id: uuid(0x11)),
        name: "Studio",
        symbol: "paintpalette.fill",
        accent: .indigo,
        branding: .initial(
            accent: .indigo,
            symbol: "paintpalette.fill"
        ),
        folders: [
            SavedFolder(
                id: folderID,
                title: "Design References",
                symbol: "folder.fill"
            )
        ],
        tabs: [
            tab(
                idByte: 0x41,
                title: "Apple Developer",
                path: "/preview/apple-developer",
                symbol: "apple.logo",
                placement: .pinned
            ),
            tab(
                idByte: 0x42,
                title: "SwiftUI Layout",
                path: "/preview/swiftui-layout",
                symbol: "rectangle.3.group.fill",
                placement: .saved,
                folderID: folderID
            ),
            tab(
                idByte: 0x43,
                title: "Crest Notes",
                path: "/preview/crest-notes",
                symbol: "note.text",
                placement: .current
            ),
            BrowserTab.startPage(
                id: TabID(rawValue: uuid(0x44)),
                lastActivatedAt: Date(timeIntervalSince1970: 0)
            ),
        ],
        selectedTabID: TabID(rawValue: uuid(0x43))
    )

    @MainActor
    static func makeBrowser() -> BrowserStore {
        BrowserStore(
            session: BrowserSession(
                spaces: [space],
                selectedSpaceID: spaceID
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
    }

    @MainActor
    static func makePages() -> BrowserPagePool {
        BrowserPagePool(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )
    }

    @MainActor
    static func makeSpaceAccess() -> BrowserSpaceAccessController {
        BrowserSpaceAccessController(
            authenticator: BrowserSidebarPreviewAuthenticator()
        )
    }

    @MainActor
    static func makeUtilityPresentation(
        surface: BrowserUtilitySurface? = nil
    ) -> BrowserUtilityPresentationState {
        let presentation = BrowserUtilityPresentationState()
        if let surface {
            presentation.present(surface)
        }
        return presentation
    }

    @MainActor
    static func makeInteractionActions() -> BrowserSidebarInteractionActions {
        BrowserSidebarInteractionActions(
            selectSpace: { _ in },
            settleSpaceSelection: { _ in },
            presentExtensions: { _ in },
            presentSpaceSettings: { _ in },
            createSpace: {},
            dismissUtilityOnBlankSpace: {},
            confirmClearHistory: { _ in },
            handleAuxiliaryMouseAction: { _ in }
        )
    }

    @MainActor
    static func makeUtilityActions(
        browser: BrowserStore,
        pages: BrowserPagePool,
        spaceAccess: BrowserSpaceAccessController
    ) -> BrowserUtilityListActions {
        BrowserSidebarUtilityCoordinator(
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess
        ).actions
    }

    private static func tab(
        idByte: UInt8,
        title: String,
        path: String,
        symbol: String,
        placement: TabPlacement,
        folderID: FolderID? = nil
    ) -> BrowserTab {
        BrowserTab(
            id: TabID(rawValue: uuid(idByte)),
            title: title,
            url: URL(fileURLWithPath: path),
            symbol: symbol,
            placement: placement,
            folderID: folderID,
            lastActivatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x53,
                0x49, 0x44,
                0x45, 0x42,
                0x41, 0x52, 0x50, 0x52, 0x45, finalByte
            ))
    }
}
