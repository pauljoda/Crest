import SwiftUI

@main
struct CrestMobileApp: App {
    @State private var browser: BrowserStore
    @State private var cloudSync: BrowserCloudSyncController
    @State private var onboardingProgress: BrowserOnboardingProgressStore
    @State private var onboardingCoordinator: BrowserOnboardingCoordinator
    @State private var pages: MobileBrowserPageStore
    @State private var spaceAccess: BrowserSpaceAccessController
    private let permissionCenter: BrowserSitePermissionCenter
    private let pageStoreRegistry: MobileBrowserPageStoreRegistry
    private let tabStateArchive: (any BrowserTabStateArchiving)?
    private let windowStatePersistence: any BrowserWindowStatePersisting
    private let startupBehavior: BrowserStartupBehavior
    private let automaticallyPresentsOnboarding: Bool
    private let usesEphemeralWebsiteDataStores: Bool
    private let presentsInstalledApplicationUI: Bool
    /// Only an installed launch watches the kernel's pressure events. An isolated
    /// launch keeps its residency exactly where a test put it without involving
    /// the installed browser session.
    private let monitorsMemoryPressure: Bool

    init() {
        let launchEnvironment = BrowserLaunchEnvironment.current
        let forceOnboarding = launchEnvironment.forcesOnboardingWelcome
        let shouldReset = launchEnvironment.resetsSession
        let usesIsolatedLaunch = BrowserLaunchIsolationPolicy.requiresIsolation(
            launchEnvironment
        )
        presentsInstalledApplicationUI =
            BrowserLaunchIsolationPolicy.presentsInstalledApplicationUI(
                launchEnvironment
            )
        if shouldReset && !usesIsolatedLaunch {
            BrowserLinkPreferenceStore.shared.reset()
        }
        let browser =
            usesIsolatedLaunch
            ? BrowserStore.isolatedLaunch(launchEnvironment: launchEnvironment)
            : BrowserStore.production(launchEnvironment: launchEnvironment)
        let transientBrowsing = BrowserTransientBrowsingCoordinator()
        let cloudSync =
            usesIsolatedLaunch
            ? BrowserCloudSyncController.isolated(browser: browser)
            : BrowserCloudSyncController(browser: browser)
        browser.setCloudSyncChangeHandler { [weak cloudSync] in
            Task { await cloudSync?.localChangesDidStage() }
        }
        let spaceAccess = BrowserSpaceAccessController()
        let permissionCenter =
            usesIsolatedLaunch
            ? BrowserSitePermissionCenter()
            : BrowserSitePermissionCenter.production(reset: shouldReset)
        // An isolated launch keeps its WebKit session state behind the same
        // boundary as Crest's browser-session and sync owners.
        let tabStateArchive =
            usesIsolatedLaunch
            ? nil
            : BrowserTabStateArchive.production()
        let pages = MobileBrowserPageStore(
            monitorsMemoryPressure: !usesIsolatedLaunch,
            usesEphemeralWebsiteDataStores: usesIsolatedLaunch,
            permissionCenter: permissionCenter,
            downloadLedger: Self.showcaseDownloadLedger(
                launchEnvironment: launchEnvironment,
                browser: browser
            ),
            loadHTTPAuthenticationCredential: { protectionSpace, spaceID in
                try await browser.httpAuthenticationCredential(
                    for: protectionSpace,
                    in: spaceID
                )
            },
            saveHTTPAuthenticationCredential: { request, spaceID in
                try await browser.saveHTTPAuthenticationCredential(
                    username: request.username,
                    password: request.password,
                    protectionSpace: request.protectionSpace,
                    in: spaceID,
                    replacing: request.replacing
                )
            },
            tabStateArchive: tabStateArchive,
            popupTabHost: browser.popupTabHost,
            openNewTab: { url in browser.openNewTab(url: url) },
            openModifiedLink: { url, spaceID, selecting in
                browser.openNewTab(url: url, in: spaceID, selecting: selecting)
            },
            openPeek: { request in transientBrowsing.presentPeek(request) },
            stagePeek: { request in transientBrowsing.stagePeek(request) },
            commitPeek: { request in transientBrowsing.commitPeek(request) },
            cancelStagedPeek: { id in transientBrowsing.cancelStagedPeek(id: id) }
        )

        _browser = State(initialValue: browser)
        _cloudSync = State(initialValue: cloudSync)
        _onboardingProgress = State(
            initialValue: BrowserOnboardingProgressStore.launchStore(
                isIsolated: usesIsolatedLaunch,
                forceWelcome: forceOnboarding,
                forceSetup: launchEnvironment.forcesMobileOnboardingSetup
            )
        )
        let onboardingCoordinator = BrowserOnboardingCoordinator()
        _onboardingCoordinator = State(initialValue: onboardingCoordinator)
        _pages = State(initialValue: pages)
        _spaceAccess = State(initialValue: spaceAccess)
        self.permissionCenter = permissionCenter
        pageStoreRegistry = MobileBrowserPageStoreRegistry(primary: pages)
        self.tabStateArchive = tabStateArchive
        windowStatePersistence =
            usesIsolatedLaunch
            ? InMemoryBrowserWindowStatePersistence()
            : UserDefaultsBrowserWindowStatePersistence()
        automaticallyPresentsOnboarding =
            MobileBrowserAutomaticOnboardingPolicy
            .shouldPresent(
                forceOnboarding: forceOnboarding,
                usesIsolatedLaunch: usesIsolatedLaunch
            )
        startupBehavior =
            launchEnvironment.presentsShowcaseSession
            ? .waitForTabSelection
            : usesIsolatedLaunch
                ? .lastActiveTab
                : BrowserStartupPreference.behavior()
        monitorsMemoryPressure = !usesIsolatedLaunch
        usesEphemeralWebsiteDataStores = usesIsolatedLaunch
    }

    private static func showcaseDownloadLedger(
        launchEnvironment: BrowserLaunchEnvironment,
        browser: BrowserStore
    ) -> BrowserDownloadLedger {
        guard launchEnvironment.presentsShowcaseSession,
            let profileID = browser.selectedSpace?.profile.id
        else { return BrowserDownloadLedger() }
        return .showcase(profileID: profileID)
    }

    var body: some Scene {
        WindowGroup(for: BrowserWindowID.self) { $windowID in
            if presentsInstalledApplicationUI {
                MobileBrowserWindowScene(
                    id: windowID,
                    rootBrowser: browser,
                    permissionCenter: permissionCenter,
                    pageStoreRegistry: pageStoreRegistry,
                    spaceAccess: spaceAccess,
                    tabStateArchive: tabStateArchive,
                    windowStatePersistence: windowStatePersistence,
                    startupBehavior: startupBehavior,
                    monitorsMemoryPressure: monitorsMemoryPressure,
                    usesEphemeralWebsiteDataStores: usesEphemeralWebsiteDataStores,
                    onboardingProgress: onboardingProgress,
                    onboardingCoordinator: onboardingCoordinator,
                    automaticallyPresentsOnboarding: automaticallyPresentsOnboarding
                )
                .environment(cloudSync)
                .environment(onboardingCoordinator)
                .task { await cloudSync.start() }
            } else {
                EmptyView()
            }
        } defaultValue: {
            BrowserWindowID()
        }
        .commands {
            MobileBrowserCommands()
        }
    }
}
