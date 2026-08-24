import Foundation

enum BrowserRootPreviewFixture {
    static let spaceID = SpaceID(rawValue: uuid(0x21))
    static let startTabID = TabID(rawValue: uuid(0x41))
    static let space = BrowserSpace(
        id: spaceID,
        profile: BrowsingProfile(id: uuid(0x11)),
        name: "Research",
        symbol: "books.vertical.fill",
        accent: .indigo,
        branding: .initial(
            accent: .indigo,
            symbol: "books.vertical.fill"
        ),
        folders: [],
        tabs: [
            BrowserTab(
                id: TabID(rawValue: uuid(0x42)),
                title: "Apple Developer",
                url: URL(fileURLWithPath: "/preview/apple-developer"),
                symbol: "apple.logo",
                placement: .pinned,
                lastActivatedAt: Date(timeIntervalSince1970: 0)
            ),
            BrowserTab(
                id: TabID(rawValue: uuid(0x43)),
                title: "WebKit Notes",
                url: URL(fileURLWithPath: "/preview/webkit-notes"),
                symbol: "safari.fill",
                placement: .current,
                lastActivatedAt: Date(timeIntervalSince1970: 0)
            ),
            BrowserTab.startPage(
                id: startTabID,
                lastActivatedAt: Date(timeIntervalSince1970: 0)
            ),
        ],
        selectedTabID: startTabID
    )

    static let splitGroupID = SplitGroupID(rawValue: uuid(0x61))

    /// Two grouped current tabs, for previewing the split content area. Kept
    /// beside the fixture Space rather than inside it so every existing preview
    /// keeps rendering the single-page path it was written for.
    static let splitMembers: [BrowserTab] = [
        BrowserTab(
            id: TabID(rawValue: uuid(0x62)),
            title: "WebKit Notes",
            url: URL(fileURLWithPath: "/preview/webkit-notes"),
            symbol: "safari.fill",
            placement: .current,
            splitGroupID: splitGroupID,
            lastActivatedAt: Date(timeIntervalSince1970: 0)
        ),
        BrowserTab(
            id: TabID(rawValue: uuid(0x63)),
            title: "Layout Research",
            url: URL(fileURLWithPath: "/preview/layout-research"),
            symbol: "ruler.fill",
            placement: .current,
            splitGroupID: splitGroupID,
            lastActivatedAt: Date(timeIntervalSince1970: 0)
        ),
    ]

    @MainActor
    static func makeBrowser() -> BrowserStore {
        BrowserStore(
            session: BrowserSession(
                spaces: [space],
                selectedSpaceID: spaceID
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )
    }

    @MainActor
    static func makeChrome(
        state: BrowserRootPreviewState = .docked
    ) -> BrowserChromeState {
        let chrome = BrowserChromeState(sidebarIsPresented: state != .collapsed)
        if state == .commandPalette {
            chrome.presentCommandPalette()
        }
        return chrome
    }

    @MainActor
    static func makeModel(
        state: BrowserRootPreviewState = .docked
    ) -> BrowserRootModel {
        let browser = makeBrowser()
        return BrowserRootModel(
            browser: browser,
            pages: BrowserPagePool(),
            chrome: makeChrome(state: state),
            spaceAccess: BrowserSpaceAccessController(),
            windowState: makeWindowState(session: browser.session),
            startupBehavior: .showStartPage,
            persistedSidebarWidth: BrowserChromeLayout.sidebarIdealWidth
        )
    }

    @MainActor
    static func makeWindowState(
        session: BrowserSession
    ) -> BrowserWindowStateStore {
        let windowState = BrowserWindowStateStore(
            id: BrowserWindowID(rawValue: uuid(0x51)),
            session: session,
            persistence: InMemoryBrowserWindowStatePersistence()
        )
        windowState.captureSidebar(
            width: Double(BrowserChromeLayout.sidebarIdealWidth),
            isPresented: true
        )
        return windowState
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x52,
                0x4F, 0x4F,
                0x54, 0x50,
                0x52, 0x45, 0x56, 0x49, 0x45, finalByte
            ))
    }
}
