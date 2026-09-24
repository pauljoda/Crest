import SwiftUI

@main
struct CrestMobileApp: App {
    @State private var launch = BrowserApplicationLaunch { try BrowserMobileApplication() }

    var body: some Scene {
        WindowGroup(for: BrowserWindowID.self) { $windowID in
            if let application = launch.value, application.presentsInstalledApplicationUI {
                application.windowContent(id: windowID)
            } else if launch.failure != nil {
                BrowserSessionRecoveryView(launch: launch)
            } else {
                EmptyView()
            }
        } defaultValue: {
            BrowserWindowID()
        }
        .commands {
            if let application = launch.value {
                MobileBrowserCommands(shortcuts: application.shortcuts)
            }
        }
    }
}

@MainActor
private final class BrowserMobileApplication {
    let browser: BrowserStore
    let cloudSync: BrowserCloudSyncController
    let onboardingProgress: BrowserOnboardingProgressStore
    let onboardingCoordinator: BrowserOnboardingCoordinator
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    /// The app's one passkey controller, which settings show.
    let passkeyAccess: BrowserPasskeyAccessController
    let shortcuts: BrowserShortcutStore
    let sidebarWidgets: BrowserSidebarWidgetRuntime
    let permissionCenter: BrowserSitePermissionCenter
    let pageStoreRegistry: MobileBrowserPageStoreRegistry
    let mediaSessions: BrowserMediaSessionStore
    /// Every window shares one download center per browsing mode, over the
    /// process's one core.
    let downloads: MobileBrowserDownloads
    let privateDownloads: MobileBrowserDownloads
    let tabStateArchive: (any BrowserTabStateArchiving)?
    let windowLayouts: BrowserWindowLayouts
    let startupBehavior: BrowserStartupBehavior
    let automaticallyPresentsOnboarding: Bool
    let usesEphemeralWebsiteDataStores: Bool
    let presentsInstalledApplicationUI: Bool
    /// Only an installed launch watches the kernel's pressure events. An isolated
    /// launch keeps its residency exactly where a test put it without involving
    /// the installed browser session.
    let monitorsMemoryPressure: Bool

    init() throws {
        #if CREST_REVIEW_BUILD
        setenv("CREST_ISOLATED_SESSION", "1", 1)
        setenv("CREST_ISOLATED_PERSISTENCE_ID", "core-native-ui-review", 0)
        #endif
        let launchEnvironment = BrowserLaunchEnvironment.current
        let forceOnboarding = launchEnvironment.forcesOnboardingWelcome
        let shouldReset = launchEnvironment.resetsSession
        let usesIsolatedLaunch = launchEnvironment.requiresIsolation
        BrowserAutomaticQuoteSubstitutionPreference.registerDefault()
        presentsInstalledApplicationUI =
            launchEnvironment.presentsInstalledApplicationUI
        if shouldReset && !usesIsolatedLaunch {
            BrowserLinkPreferenceStore.shared.reset()
        }
        // One core per process, keeping the session file and shared by every
        // window of both browsing modes.
        let core = try BrowserStore.launchCore(for: launchEnvironment)
        let browser = try BrowserStore.production(core: core, launchEnvironment: launchEnvironment)
        BrowserAppPreferenceStore.shared.bind(
            to: browser, legacy: BrowserLegacyAppPreferences.read(for: launchEnvironment))
        let transientBrowsing = BrowserTransientBrowsingCoordinator()
        let cloudSync =
            usesIsolatedLaunch
            ? BrowserCloudSyncController.isolated(browser: browser)
            : BrowserCloudSyncController(browser: browser)
        browser.setCloudSyncChangeHandler { [weak cloudSync] in
            Task { await cloudSync?.localChangesDidStage() }
        }
        let spaceAccess = BrowserSpaceAccessController()
        browser.attachSpaceAccess(spaceAccess)
        let permissionCenter =
            usesIsolatedLaunch
            ? BrowserSitePermissionCenter()
            : BrowserSitePermissionCenter.production(reset: shouldReset)
        // The core ledger never answers or records for a locked Space. A Space
        // this app does not own has no lock of its own.
        permissionCenter.attachSpaceLockState { [weak browser, weak spaceAccess] spaceID in
            guard let spaceAccess else { return true }
            guard let space = browser?.session.space(id: spaceID) else { return false }
            return spaceAccess.isLocked(space)
        }
        // An isolated launch keeps its engine session state behind the same
        // boundary as Crest's browser-session and sync owners.
        let tabStateArchive = BrowserTabStateArchive.forLaunch(launchEnvironment)
        let mediaSessions = BrowserMediaSessionStore()
        let sidebarWidgetPreferences = BrowserSidebarWidgetPreferenceStore.launch(
            environment: launchEnvironment
        )
        let sidebarWidgets = BrowserSidebarWidgetRuntime(
            registrations: [.nowPlaying],
            sources: [mediaSessions],
            preferences: sidebarWidgetPreferences
        )
        if launchEnvironment.presentsShowcaseSession, let profileID = browser.selectedSpace?.profile.id {
            core.addShowcaseDownloads(profileID: profileID)
        }
        let downloads = MobileBrowserDownloads(
            core: core,
            permissionCenter: permissionCenter,
            loadCredential: { protectionSpace, spaceID in
                try await browser.httpAuthenticationCredential(for: protectionSpace, in: spaceID)
            },
            saveCredential: { request, spaceID in
                try await browser.saveHTTPAuthenticationCredential(
                    username: request.username,
                    password: request.password,
                    protectionSpace: request.protectionSpace,
                    in: spaceID,
                    replacing: request.replacing
                )
            }
        )
        let privateDownloads = MobileBrowserDownloads(
            core: core,
            browsingMode: .privateBrowsing,
            permissionCenter: BrowserSitePermissionCenter()
        )
        let pages = MobileBrowserPageStore(
            monitorsMemoryPressure: !usesIsolatedLaunch,
            usesEphemeralWebsiteDataStores: usesIsolatedLaunch,
            permissionCenter: permissionCenter,
            mediaSessionStore: mediaSessions,
            downloads: downloads,
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
            linkDestinationHost: BrowserLinkDestinationHost(browser: browser, spaceAccess: spaceAccess),
            openNewTab: { url in browser.openNewTab(url: url) },
            openModifiedLink: { url, spaceID, selecting in
                guard
                    let tabID = browser.openNewTab(
                        url: url,
                        in: spaceID,
                        selecting: selecting
                    ),
                    let space = browser.session.space(id: spaceID),
                    let tab = space.tabs.first(where: { $0.id == tabID })
                else { return nil }
                return BrowserModifiedLinkRegistration(tab: tab, space: space, session: browser.presented)
            },
            backgroundPageDidUpdate: { browser.updateBackgroundPage($0) },
            openPeek: { request in transientBrowsing.presentPeek(request) }
        )

        self.browser = browser
        self.cloudSync = cloudSync
        onboardingProgress = BrowserOnboardingProgressStore.launchStore(
            isIsolated: usesIsolatedLaunch,
            forceWelcome: forceOnboarding,
            forceSetup: launchEnvironment.forcesMobileOnboardingSetup,
            persistentIsolationID: launchEnvironment.persistentIsolationID
        )
        let onboardingCoordinator = BrowserOnboardingCoordinator()
        self.onboardingCoordinator = onboardingCoordinator
        self.pages = pages
        self.spaceAccess = spaceAccess
        passkeyAccess = BrowserPasskeyAccessController(core: core)
        self.sidebarWidgets = sidebarWidgets
        // A hardware keyboard on iPad reads the same rebindable command table
        // the Mac menu bar does, composed exactly the way the Mac composes it.
        shortcuts = BrowserShortcutStore.launch(
            usesIsolatedLaunch: usesIsolatedLaunch,
            reset: shouldReset
        )
        self.permissionCenter = permissionCenter
        pageStoreRegistry = MobileBrowserPageStoreRegistry(primary: pages)
        self.mediaSessions = mediaSessions
        self.downloads = downloads
        self.privateDownloads = privateDownloads
        self.tabStateArchive = tabStateArchive
        if usesIsolatedLaunch {
            windowLayouts = BrowserWindowLayouts(
                defaults: launchEnvironment.persistentIsolationID.flatMap {
                    UserDefaults(suiteName: BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: $0))
                })
        } else {
            windowLayouts = BrowserWindowLayouts(defaults: .standard)
        }
        // The core carries what each scene showed into its own records once;
        // scenes restore from them later, and launch cleanup keeps every tab
        // one of them will show.
        windowLayouts.adoptLegacyRecords(into: core)
        browser.sweepAtLaunch()
        automaticallyPresentsOnboarding =
            MobileBrowserAutomaticOnboardingPolicy
            .shouldPresent(
                forceOnboarding: forceOnboarding,
                usesIsolatedLaunch: usesIsolatedLaunch
            )
        startupBehavior = browser.startupBehavior(for: launchEnvironment)
        monitorsMemoryPressure = !usesIsolatedLaunch
        usesEphemeralWebsiteDataStores = usesIsolatedLaunch
    }

    func windowContent(id windowID: BrowserWindowID) -> some View {
        MobileBrowserWindowScene(
            id: windowID,
            rootBrowser: browser,
            permissionCenter: permissionCenter,
            pageStoreRegistry: pageStoreRegistry,
            spaceAccess: spaceAccess,
            tabStateArchive: tabStateArchive,
            windowLayouts: windowLayouts,
            startupBehavior: startupBehavior,
            monitorsMemoryPressure: monitorsMemoryPressure,
            usesEphemeralWebsiteDataStores: usesEphemeralWebsiteDataStores,
            onboardingProgress: onboardingProgress,
            onboardingCoordinator: onboardingCoordinator,
            automaticallyPresentsOnboarding: automaticallyPresentsOnboarding,
            mediaSessions: mediaSessions,
            downloads: downloads,
            privateDownloads: privateDownloads,
            sidebarWidgets: sidebarWidgets
        )
        .environment(cloudSync)
        .environment(onboardingCoordinator)
        .environment(passkeyAccess)
        .environment(
            \.browserSidebarWidgetRuntime,
            sidebarWidgets
        )
        .task {
            self.browser.family.configureSpaceDataCleanup(self.pageStoreRegistry, from: self.browser)
            await self.cloudSync.start()
        }
    }
}
