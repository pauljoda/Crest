import SwiftUI
import UserNotifications

/// Owns the existing app services independently of SwiftUI's process entry
/// point. Both the normal App and a native engine host mount the same window
/// content from this composition.
@MainActor
final class BrowserMacApplication {
    let browser: BrowserStore
    let cloudSync: BrowserCloudSyncController
    let onboardingProgress: BrowserOnboardingProgressStore
    let onboardingCoordinator: BrowserOnboardingCoordinator
    let pages: BrowserPagePool
    let chrome: BrowserChromeState
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let windowCoordinator: BrowserMacWindowCoordinator
    let privateBrowser: BrowserStore
    let privatePages: BrowserPagePool
    let privateChrome: BrowserChromeState
    let privateTransientBrowsing: BrowserTransientBrowsingCoordinator
    let spaceAccess: BrowserSpaceAccessController
    let shortcuts: BrowserShortcutStore
    let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    let windowTransparency: BrowserWindowTransparencyStore
    let splitFocus: BrowserSplitFocusPreferenceStore
    let softwareUpdates: BrowserSoftwareUpdateService
    let sidebarWidgets: BrowserSidebarWidgetRuntime
    let pagePoolRegistry: BrowserPagePoolRegistry
    let systemNowPlaying: BrowserSystemNowPlayingCoordinator?
    let startupBehavior: BrowserStartupBehavior
    let presentsInstalledApplicationUI: Bool

    init(pageClosePreparation: (any BrowserPageClosePreparing)? = nil,
        profileRemover: any BrowserEngineProfileRemoving = WebKitBrowserWebsiteDataStoreRemover()) throws {
        #if CREST_REVIEW_BUILD
        setenv("CREST_ISOLATED_SESSION", "1", 1)
        #if CREST_CHROMIUM_HOST
        setenv("CREST_ISOLATED_PERSISTENCE_ID", "chromium-native-ui-review", 0)
        #else
        setenv("CREST_ISOLATED_PERSISTENCE_ID", "core-native-ui-review", 0)
        #endif
        #endif
        let launchEnvironment = BrowserLaunchEnvironment.current
        let shouldReset = launchEnvironment.resetsSession
        let usesIsolatedLaunch = launchEnvironment.requiresIsolation
        let usesEphemeralProfileStorage =
            launchEnvironment.usesEphemeralProfileStorage
        BrowserMacWebTextAssistancePolicy.configure()
        BrowserWebKitFeatureFlagStore.configureForLaunch(
            usesIsolatedLaunch: usesIsolatedLaunch
        )
        let utilityDefaults: UserDefaults? = usesIsolatedLaunch ? nil : .standard
        presentsInstalledApplicationUI =
            launchEnvironment.presentsInstalledApplicationUI
        // Import review and manual setup belong to the currently open wizard.
        // Retire drafts written by earlier releases before any new window opens.
        if !usesIsolatedLaunch {
            BrowserOnboardingLegacyDraftCleanup.clear()
        }
        if shouldReset && !usesIsolatedLaunch {
            BrowserLinkPreferenceStore.shared.reset()
        }
        let browser = try BrowserStore.production(launchEnvironment: launchEnvironment)
        let privateBrowser = BrowserStore.privateBrowsing()
        let cloudSync =
            usesIsolatedLaunch
            ? BrowserCloudSyncController.isolated(browser: browser)
            : BrowserCloudSyncController(browser: browser)
        browser.setCloudSyncChangeHandler { [weak cloudSync] in
            Task { await cloudSync?.localChangesDidStage() }
        }
        let transientBrowsing = BrowserTransientBrowsingCoordinator()
        let privateTransientBrowsing = BrowserTransientBrowsingCoordinator()
        let spaceAccess = BrowserSpaceAccessController()
        browser.attachSpaceAccess(spaceAccess)
        privateBrowser.attachSpaceAccess(spaceAccess)
        let spaceSettingsPresentation =
            BrowserSpaceSettingsPresentationState()
        let permissionCenter =
            usesIsolatedLaunch
            ? BrowserSitePermissionCenter()
            : BrowserSitePermissionCenter.production(reset: shouldReset)
        // The core ledger never answers or records for a locked Space. A Space
        // this app does not own has no lock of its own.
        permissionCenter.attachSpaceLockState { [weak browser, weak privateBrowser, weak spaceAccess] spaceID in
            guard let spaceAccess else { return true }
            guard let space = browser?.session.space(id: spaceID) ?? privateBrowser?.session.space(id: spaceID) else { return false }
            return spaceAccess.isLocked(space)
        }
        let hostedNotificationCenter = BrowserHostedWebNotificationSystemCenter()
        let sidebarDefaults: UserDefaults?
        if usesIsolatedLaunch, let isolationID = launchEnvironment.persistentIsolationID {
            sidebarDefaults = UserDefaults(
                suiteName: BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: isolationID))
        } else {
            sidebarDefaults = utilityDefaults
        }
        // An isolated launch keeps its engine session state behind the same
        // boundary as Crest's browser-session and sync owners.
        let tabStateArchive = BrowserTabStateArchive.forLaunch(launchEnvironment)
        let mediaSessions = BrowserMediaSessionStore()
        let systemNowPlaying =
            presentsInstalledApplicationUI
            ? BrowserSystemNowPlayingCoordinator(store: mediaSessions)
            : nil
        systemNowPlaying?.start()
        let isolatedSoftwareUpdateFeed =
            launchEnvironment.isolatedSoftwareUpdateFeedURL
        let softwareUpdates = BrowserSoftwareUpdateService(
            isEnabled: presentsInstalledApplicationUI
                && (!usesIsolatedLaunch || isolatedSoftwareUpdateFeed != nil),
            preferences: usesIsolatedLaunch ? nil : .standard,
            defaultChannel: isolatedSoftwareUpdateFeed.map { _ in .development },
            feedURLOverride: isolatedSoftwareUpdateFeed
        )
        if usesIsolatedLaunch,
            let fixture = launchEnvironment.softwareUpdateWidgetFixture
        {
            softwareUpdates.presentIsolatedSidebarWidgetFixture(fixture)
        }
        let sidebarWidgetPreferences = BrowserSidebarWidgetPreferenceStore.launch(
            environment: launchEnvironment
        )
        let sidebarWidgets = BrowserSidebarWidgetRuntime(
            registrations: [.softwareUpdate, .nowPlaying],
            sources: [softwareUpdates.widgetSource, mediaSessions],
            preferences: sidebarWidgetPreferences
        )
        let pages = BrowserPagePool(
            monitorsMemoryPressure: !usesIsolatedLaunch,
            usesEphemeralWebsiteDataStores: usesEphemeralProfileStorage,
            permissionCenter: permissionCenter,
            hostedNotificationCenter: hostedNotificationCenter,
            mediaSessionStore: mediaSessions,
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
            profileRemover: profileRemover,
            tabStateArchive: tabStateArchive,
            popupTabHost: browser.popupTabHost,
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
                return BrowserModifiedLinkRegistration(
                    tab: tab,
                    space: space,
                    session: browser.session
                )
            },
            backgroundPageDidUpdate: { update in
                browser.updateTabFromPage(
                    url: update.url,
                    title: update.title,
                    faviconData: update.faviconData,
                    iconAccent: update.iconAccent,
                    for: update.tabID,
                    matching: update.assignment
                )
                if let url = update.completedNavigationURL {
                    browser.recordVisit(
                        url: url,
                        title: update.title,
                        matching: update.assignment
                    )
                }
                return browser.session
            },
            openPeek: { request in transientBrowsing.presentPeek(request) },
            handleLinkDrag: { transientBrowsing.handleLinkDrag($0) },
            splitLinkHost: browser.splitLinkHost,
            linkDestinationHost: BrowserLinkDestinationHost(browser: browser, spaceAccess: spaceAccess),
            activateHostedNotificationSource: { spaceID, tabID in
                browser.selectSpace(spaceID)
                browser.selectTab(tabID)
            }
        )
        let privatePages = BrowserPagePool(
            // A private window can hold as many live web views as a standard one,
            // and they are the least surprising ones to lose: a private page comes
            // back by reload because it deliberately archives no session state.
            monitorsMemoryPressure: !usesIsolatedLaunch,
            browsingMode: .privateBrowsing,
            permissionCenter: BrowserSitePermissionCenter(),
            profileRemover: profileRemover,
            // The private pool answers to the private store, so a popup from a
            // private page can only ever land in a private tab.
            popupTabHost: privateBrowser.popupTabHost,
            openNewTab: { url in privateBrowser.openNewTab(url: url) },
            openModifiedLink: { url, spaceID, selecting in
                guard
                    let tabID = privateBrowser.openNewTab(
                        url: url,
                        in: spaceID,
                        selecting: selecting
                    ),
                    let space = privateBrowser.session.space(id: spaceID),
                    let tab = space.tabs.first(where: { $0.id == tabID })
                else { return nil }
                return BrowserModifiedLinkRegistration(
                    tab: tab,
                    space: space,
                    session: privateBrowser.session
                )
            },
            backgroundPageDidUpdate: { update in
                privateBrowser.updateTabFromPage(
                    url: update.url,
                    title: update.title,
                    faviconData: update.faviconData,
                    iconAccent: update.iconAccent,
                    for: update.tabID,
                    matching: update.assignment
                )
                if let url = update.completedNavigationURL {
                    privateBrowser.recordVisit(
                        url: url,
                        title: update.title,
                        matching: update.assignment
                    )
                }
                return privateBrowser.session
            },
            openPeek: { request in privateTransientBrowsing.presentPeek(request) },
            handleLinkDrag: { privateTransientBrowsing.handleLinkDrag($0) },
            splitLinkHost: privateBrowser.splitLinkHost,
            linkDestinationHost: BrowserLinkDestinationHost(browser: privateBrowser, spaceAccess: spaceAccess)
        )
        privatePages.connectPictureInPictureSourceSelection(
            to: privateBrowser,
            spaceAccess: spaceAccess
        )
        browser.tabLinkProvider = pages
        privateBrowser.tabLinkProvider = privatePages
        browser.tabCopying = pages
        privateBrowser.tabCopying = privatePages
        let windowStatePersistence: any BrowserWindowStatePersisting =
            if let sidebarDefaults {
                UserDefaultsBrowserWindowStatePersistence(defaults: sidebarDefaults)
            } else {
                InMemoryBrowserWindowStatePersistence()
            }
        let onboardingProgress = BrowserOnboardingProgressStore.launchStore(
            isIsolated: usesIsolatedLaunch,
            forceWelcome: launchEnvironment.forcesOnboardingWelcome,
            forceSetup: launchEnvironment.forcesMacOnboardingSetup,
            persistentIsolationID: launchEnvironment.persistentIsolationID
        )
        let startupBehavior = BrowserCorePolicy.startupBehavior(
            for: launchEnvironment,
            hasActiveLaunchGate: onboardingProgress.isLaunchGateActive
        )
        let mainWindowState = BrowserWindowStateStore(
            id: .main,
            session: browser.session,
            persistence: windowStatePersistence
        )
        self.browser = browser
        self.cloudSync = cloudSync
        self.onboardingProgress = onboardingProgress
        self.onboardingCoordinator = BrowserOnboardingCoordinator()
        self.chrome = BrowserChromeState(
                sidebarIsPresented: mainWindowState.sidebarIsPresented ?? true,
                utilityPresentation: BrowserUtilityPresentationState(
                    defaults: utilityDefaults
                )
            )
        self.transientBrowsing = transientBrowsing
        self.windowCoordinator = BrowserMacWindowCoordinator(
                browser: browser, pages: pages, spaceAccess: spaceAccess,
                windowStatePersistence: windowStatePersistence)
        self.privateBrowser = privateBrowser
        self.privateChrome = BrowserChromeState(
                utilityPresentation: BrowserUtilityPresentationState(
                    defaults: utilityDefaults
                )
            )
        self.privateTransientBrowsing = privateTransientBrowsing
        self.spaceAccess = spaceAccess
        self.spaceSettingsPresentation = spaceSettingsPresentation
        let shortcuts = BrowserShortcutStore.launch(
            usesIsolatedLaunch: usesIsolatedLaunch,
            reset: shouldReset
        )
        self.shortcuts = shortcuts
        self.windowTransparency = BrowserWindowTransparencyStore.launch(
                usesIsolatedLaunch: usesIsolatedLaunch
            )
        self.splitFocus = BrowserSplitFocusPreferenceStore.launch(
                usesIsolatedLaunch: usesIsolatedLaunch
            )
        self.softwareUpdates = softwareUpdates
        self.sidebarWidgets = sidebarWidgets
        self.pages = pages
        self.privatePages = privatePages
        pagePoolRegistry = BrowserPagePoolRegistry(primary: pages, spaceAccess: spaceAccess,
            closePreparation: pageClosePreparation)
        self.systemNowPlaying = systemNowPlaying
        self.startupBehavior = startupBehavior
        browser.family.configureSpaceDataCleanup(pagePoolRegistry, from: browser)
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

    func settingsTabContent(
        browser: BrowserStore, pages: BrowserPagePool,
        presentation: BrowserSpaceSettingsPresentationState? = nil
    ) -> BrowserSettingsTabContent {
        BrowserSettingsTabContent { [self] runtime in
            BrowserSettingsView(
                browser: browser.profileSettingsBrowser, pages: pages, cloudSync: cloudSync,
                spaceAccess: spaceAccess, dataDeleter: pagePoolRegistry, shortcuts: shortcuts,
                onboardingCoordinator: onboardingCoordinator, spaceSettingsPresentation: presentation ?? spaceSettingsPresentation,
                usesLiveSidebar: !browser.isTemporaryWorkspace,
                tabState: runtime.model(BrowserSettingsTabState.self) { BrowserSettingsTabState() },
                tabAssignment: runtime.assignment
            )
        }
    }

    @ViewBuilder
    func browserWindowContent(_ request: BrowserMacWindowRequest) -> some View {
        if let model = windowCoordinator.model(for: request) {
            BrowserMacWindowScene(
                model: model, coordinator: windowCoordinator,
                pagePoolRegistry: pagePoolRegistry, spaceAccess: spaceAccess,
                spaceSettingsPresentation: spaceSettingsPresentation,
                startupBehavior: request == .initial ? startupBehavior : .lastActiveTab,
                shortcuts: shortcuts, sidebarWidgets: sidebarWidgets, softwareUpdates: softwareUpdates
            )
            .environment(
                \.browserSettingsTabContent,
                settingsTabContent(
                    browser: model.browser, pages: model.pages, presentation: model.spaceSettingsPresentation)
            )
            .environment(windowTransparency)
            .environment(splitFocus)
            .environment(softwareUpdates)
            .environment(\.browserSidebarWidgetRuntime, sidebarWidgets)
        } else {
            Color.clear.background(
                BrowserMacWindowAttachment(
                    attach: { $0.close() }, focusChanged: { _ in }, close: {}))
        }
    }

    var privateWindowContent: some View {
        BrowserRootView(
            browser: privateBrowser,
            pages: privatePages,
            chrome: privateChrome,
            transientBrowsing: privateTransientBrowsing,
            startupBehavior: .lastActiveTab,
            shortcuts: shortcuts
        )
        .modifier(BrowserChromeAppearancePersistence())
        .environment(windowTransparency)
        .environment(splitFocus)
        .environment(softwareUpdates)
        .environment(
            \.browserSidebarWidgetRuntime,
            sidebarWidgets
        )
        .frame(minWidth: 900, minHeight: 600)
        .preferredColorScheme(.dark)
        .environment(
            \.browserSettingsTabContent, settingsTabContent(browser: privateBrowser, pages: privatePages)
        )
        .background(
            BrowserMacWindowAttachment(
                attach: { window in
                    self.privatePages.bindNativeWindow(window)
                    self.privatePages.setWindowFocused(window.isKeyWindow)
                },
                focusChanged: { self.privatePages.setWindowFocused($0) },
                close: {
                    self.privatePages.setWindowFocused(false)
                    self.privatePages.bindNativeWindow(nil)
                }
            )
        )
        .onDisappear {
            #if !CREST_CHROMIUM_HOST
            self.closePrivateBrowsingWindow()
            #endif
        }
    }

    func closePrivateBrowsingWindow() {
        let closingSession = privateBrowser.session
        privatePages.closePrivateBrowsingSession(closingSession)
        privateBrowser.resetPrivateBrowsingSession()
        privateChrome.dismissCommandPalette()
        privateTransientBrowsing.dismissPeek()
    }

}
