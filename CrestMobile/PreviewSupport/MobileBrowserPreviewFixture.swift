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
            branding: .house(.lion, symbol: "briefcase.fill"),
            folders: [],
            tabs: []
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
            branding: .house(.winter, symbol: "house.fill"),
            folders: [],
            tabs: []
        )
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [space, alternateSpace]
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
        let contentRuleListProvider = BrowserContentRuleListProvider(
            core: browser.core,
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
            browser: browser,
            persistence: InMemoryBrowserWindowStatePersistence()
        )
        windowState.captureSidebar(
            width: Double(MobileBrowserRootLayout.defaultRegularSidebarWidth),
            isPresented: true
        )
        cloudSync = .isolated(browser: browser)
        onboardingCoordinator = BrowserOnboardingCoordinator()
        spaceAccess = BrowserSpaceAccessController(
            authenticator: BrowserPreviewAuthenticator(result: false)
        )
        passkeyAccess = BrowserPasskeyAccessController(
            core: browser.core,
            capabilityCheck: { true },
            deviceConfigurationCheck: { .configured },
            authorizationCheck: { .authorized },
            authorizationRequester: { .authorized }
        )
    }
}
