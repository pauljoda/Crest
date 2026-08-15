import Foundation

@MainActor
struct MobileBrowserPreviewFixture {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let cloudSync: BrowserCloudSyncController
    let onboardingCoordinator: BrowserOnboardingCoordinator
    let spaceAccess: BrowserSpaceAccessController
    let passkeyAccess: BrowserPasskeyAccessController
    let windowState: BrowserWindowStateStore
    let space: BrowserSpace
    let alternateSpace: BrowserSpace

    init() {
        let space = BrowserSpace(
            id: SpaceID(
                rawValue: UUID(
                    uuid: (
                        0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                        0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
                    )
                )
            ),
            profile: BrowsingProfile(
                id: UUID(
                    uuid: (
                        0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                        0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
                    )
                )
            ),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: [],
            selectedTabID: nil
        )
        let alternateSpace = BrowserSpace(
            id: SpaceID(
                rawValue: UUID(
                    uuid: (
                        0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                        0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02
                    )
                )
            ),
            profile: BrowsingProfile(
                id: UUID(
                    uuid: (
                        0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                        0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02
                    )
                )
            ),
            name: "Personal",
            symbol: "house.fill",
            accent: .orange,
            folders: [],
            tabs: [],
            selectedTabID: nil
        )
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [space, alternateSpace],
                selectedSpaceID: space.id
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
        let contentRuleListProvider = BrowserContentRuleListProvider(
            ruleListStore: nil
        )
        let pages = MobileBrowserPageStore(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true,
            permissionCenter: BrowserSitePermissionCenter(),
            contentRuleListProvider: contentRuleListProvider
        )

        self.space = space
        self.alternateSpace = alternateSpace
        self.browser = browser
        self.pages = pages
        windowState = BrowserWindowStateStore(
            id: BrowserWindowID(
                rawValue: UUID(
                    uuid: (
                        0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                        0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
                    )
                )
            ),
            session: browser.session,
            persistence: InMemoryBrowserWindowStatePersistence()
        )
        windowState.captureSidebar(
            width: Double(MobileBrowserRootLayout.defaultRegularSidebarWidth),
            isPresented: true
        )
        cloudSync = .isolated(browser: browser)
        onboardingCoordinator = BrowserOnboardingCoordinator()
        spaceAccess = BrowserSpaceAccessController(
            authenticator: MobileBrowserPreviewAuthenticator()
        )
        passkeyAccess = BrowserPasskeyAccessController(
            capabilityCheck: { true },
            deviceConfigurationCheck: { .configured },
            authorizationCheck: { .authorized },
            authorizationRequester: { .authorized }
        )
    }
}
