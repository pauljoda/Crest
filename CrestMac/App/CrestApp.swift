import SwiftUI

@main
struct CrestApp: App {
    @State private var browser: BrowserStore
    @State private var cloudSync: BrowserCloudSyncController
    @State private var onboardingProgress: BrowserOnboardingProgressStore
    @State private var onboardingCoordinator: BrowserOnboardingCoordinator
    @State private var pages: BrowserPagePool
    @State private var chrome: BrowserChromeState
    @State private var transientBrowsing: BrowserTransientBrowsingCoordinator
    @State private var mainWindowState: BrowserWindowStateStore
    @State private var privateBrowser: BrowserStore
    @State private var privatePages: BrowserPagePool
    @State private var privateChrome: BrowserChromeState
    @State private var privateTransientBrowsing: BrowserTransientBrowsingCoordinator
    @State private var spaceAccess: BrowserSpaceAccessController
    @State private var shortcuts: BrowserShortcutStore
    @State private var spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    @State private var windowTransparency: BrowserWindowTransparencyStore
    @State private var splitFocus: BrowserSplitFocusPreferenceStore
    @State private var softwareUpdates: BrowserSoftwareUpdateService
    @State private var sidebarWidgets: BrowserSidebarWidgetRuntime
    private let extensionControllerPool: BrowserExtensionControllerPool
    private let extensionCommandMonitor: BrowserExtensionCommandMonitor
    private let pagePoolRegistry: BrowserPagePoolRegistry
    private let systemNowPlaying: BrowserSystemNowPlayingCoordinator?
    private let startupBehavior: BrowserStartupBehavior
    private let presentsInstalledApplicationUI: Bool

    init() {
        let launchEnvironment = BrowserLaunchEnvironment.current
        let shouldReset = launchEnvironment.resetsSession
        let usesIsolatedLaunch = BrowserLaunchIsolationPolicy.requiresIsolation(
            launchEnvironment
        )
        BrowserAutomaticQuoteSubstitutionPreference.registerDefault()
        BrowserWebKitFeatureFlagStore.configureForLaunch(
            usesIsolatedLaunch: usesIsolatedLaunch
        )
        let utilityDefaults: UserDefaults? = usesIsolatedLaunch ? nil : .standard
        presentsInstalledApplicationUI =
            BrowserLaunchIsolationPolicy.presentsInstalledApplicationUI(
                launchEnvironment
            )
        // Import review and manual setup belong to the currently open wizard.
        // Retire drafts written by earlier releases before any new window opens.
        if !usesIsolatedLaunch {
            BrowserOnboardingLegacyDraftCleanup.clear()
        }
        if shouldReset && !usesIsolatedLaunch {
            BrowserLinkPreferenceStore.shared.reset()
        }
        let browser =
            usesIsolatedLaunch
            ? BrowserStore.isolatedLaunch(launchEnvironment: launchEnvironment)
            : BrowserStore.production(launchEnvironment: launchEnvironment)
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
        let spaceSettingsPresentation =
            BrowserSpaceSettingsPresentationState()
        let permissionCenter =
            usesIsolatedLaunch
            ? BrowserSitePermissionCenter()
            : BrowserSitePermissionCenter.production(reset: shouldReset)
        let hostedNotificationCenter = BrowserHostedWebNotificationSystemCenter()
        let extensionControllerPool =
            usesIsolatedLaunch
            ? BrowserExtensionControllerPool(
                storedResourcePreparer:
                    BrowserStoreWebExtensionStoredResourcePreparer()
            )
            : BrowserExtensionControllerPool.production(
                storedResourcePreparer:
                    BrowserStoreWebExtensionStoredResourcePreparer()
            )
        let privateExtensionControllerPool = BrowserExtensionControllerPool()
        extensionControllerPool.setNativeMessagingHandler(
            usesIsolatedLaunch
                ? BrowserNativeMessagingService(
                    capability:
                        BrowserPlatformExtensionNativeMessagingCapability
                        .currentBuild,
                    resolver: BrowserNativeMessagingHostManifestResolver(
                        searchDirectories: []
                    ),
                    webpageMenuRegistry:
                        extensionControllerPool.webpageMenuRegistry
                )
                : BrowserNativeMessagingService.production(
                    webpageMenuRegistry:
                        extensionControllerPool.webpageMenuRegistry
                )
        )
        extensionControllerPool.setCommandSettingsHandler {
            route,
            spaceID in
            guard let space = browser.session.space(id: spaceID) else { return }
            spaceSettingsPresentation.presentExtensionCommandSettings(
                route,
                assignment: BrowserSpaceRuntimeAssignment(space: space)
            )
        }
        // An isolated launch keeps the updates UI reachable for validation but
        // starts with the cadence switched off, so a fixture launch never
        // reaches the Chrome Web Store on its own.
        let extensionUpdatePreferences: any BrowserExtensionUpdatePreferencesPersisting =
            usesIsolatedLaunch
            ? InMemoryBrowserExtensionUpdatePreferencesPersistence(
                preferences: BrowserExtensionUpdatePreferences(
                    isAutomaticUpdateEnabled: false
                )
            )
            : UserDefaultsBrowserExtensionUpdatePreferencesPersistence()
        let extensionUpdateMetadata: any BrowserExtensionUpdateMetadataPersisting =
            usesIsolatedLaunch
            ? InMemoryBrowserExtensionUpdateMetadataPersistence()
            : UserDefaultsBrowserExtensionUpdateMetadataPersistence()
        extensionControllerPool.setUpdateModel(
            BrowserExtensionUpdateModel(
                preferencesPersistence: extensionUpdatePreferences,
                updateMetadataPersistence: extensionUpdateMetadata,
                checker: BrowserChromeWebStoreUpdateChecker(),
                applier: BrowserChromeWebStoreUpdater(
                    pool: extensionControllerPool,
                    spaces: { browser.session.spaces }
                )
            )
        )
        // An isolated launch keeps its WebKit session state behind the same
        // boundary as Crest's browser-session and sync owners.
        let tabStateArchive =
            usesIsolatedLaunch
            ? nil
            : BrowserTabStateArchive.production()
        let mediaSessions = BrowserMediaSessionStore()
        let systemNowPlaying =
            presentsInstalledApplicationUI
            ? BrowserSystemNowPlayingCoordinator(store: mediaSessions)
            : nil
        systemNowPlaying?.start()
        let softwareUpdates = BrowserSoftwareUpdateService(
            isEnabled: presentsInstalledApplicationUI && !usesIsolatedLaunch
        )
        if usesIsolatedLaunch,
            let fixture = launchEnvironment.softwareUpdateWidgetFixture
        {
            softwareUpdates.presentIsolatedSidebarWidgetFixture(fixture)
        }
        let sidebarWidgets = BrowserSidebarWidgetRuntime(
            registrations: [.softwareUpdate, .nowPlaying],
            sources: [softwareUpdates.widgetSource, mediaSessions]
        )
        let pages = BrowserPagePool(
            monitorsMemoryPressure: !usesIsolatedLaunch,
            usesEphemeralWebsiteDataStores: usesIsolatedLaunch,
            extensionControllerPool: extensionControllerPool,
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
            splitLinkHost: browser.splitLinkHost,
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
            extensionControllerPool: privateExtensionControllerPool,
            permissionCenter: BrowserSitePermissionCenter(),
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
            splitLinkHost: privateBrowser.splitLinkHost
        )
        extensionControllerPool.connect(browser: browser, pageProvider: pages)
        privateExtensionControllerPool.connect(
            browser: privateBrowser,
            pageProvider: privatePages
        )
        let windowStatePersistence: any BrowserWindowStatePersisting =
            usesIsolatedLaunch
            ? InMemoryBrowserWindowStatePersistence()
            : UserDefaultsBrowserWindowStatePersistence()
        let startupBehavior =
            usesIsolatedLaunch
            ? BrowserStartupBehavior.lastActiveTab
            : BrowserStartupPreference.behavior()
        let mainWindowState = BrowserWindowStateStore(
            id: .main,
            session: browser.session,
            persistence: windowStatePersistence
        )
        _browser = State(initialValue: browser)
        _cloudSync = State(initialValue: cloudSync)
        _onboardingProgress = State(
            initialValue: BrowserOnboardingProgressStore.launchStore(
                isIsolated: usesIsolatedLaunch,
                forceWelcome: launchEnvironment.forcesOnboardingWelcome,
                // A machine that has already finished setup always answers the
                // welcome step with "Open Crest", so the steps past it are only
                // reachable when the launch is told to treat setup as unfinished.
                forceSetup: launchEnvironment.forcesMacOnboardingSetup
            )
        )
        _onboardingCoordinator = State(initialValue: BrowserOnboardingCoordinator())
        _chrome = State(
            initialValue: BrowserChromeState(
                sidebarIsPresented: mainWindowState.sidebarIsPresented ?? true,
                utilityPresentation: BrowserUtilityPresentationState(
                    defaults: utilityDefaults
                )
            )
        )
        _transientBrowsing = State(initialValue: transientBrowsing)
        _mainWindowState = State(initialValue: mainWindowState)
        _privateBrowser = State(initialValue: privateBrowser)
        _privateChrome = State(
            initialValue: BrowserChromeState(
                utilityPresentation: BrowserUtilityPresentationState(
                    defaults: utilityDefaults
                )
            )
        )
        _privateTransientBrowsing = State(initialValue: privateTransientBrowsing)
        _spaceAccess = State(initialValue: spaceAccess)
        _spaceSettingsPresentation = State(
            initialValue: spaceSettingsPresentation
        )
        let shortcuts = BrowserShortcutStore.launch(
            usesIsolatedLaunch: usesIsolatedLaunch,
            reset: shouldReset
        )
        _shortcuts = State(initialValue: shortcuts)
        _windowTransparency = State(
            initialValue: BrowserWindowTransparencyStore.launch(
                usesIsolatedLaunch: usesIsolatedLaunch
            )
        )
        _splitFocus = State(
            initialValue: BrowserSplitFocusPreferenceStore.launch(
                usesIsolatedLaunch: usesIsolatedLaunch
            )
        )
        _softwareUpdates = State(initialValue: softwareUpdates)
        _sidebarWidgets = State(initialValue: sidebarWidgets)
        _pages = State(initialValue: pages)
        _privatePages = State(initialValue: privatePages)
        self.extensionControllerPool = extensionControllerPool
        extensionCommandMonitor = BrowserExtensionCommandMonitor(
            browser: browser,
            extensionControllerPool: extensionControllerPool,
            shortcuts: shortcuts
        )
        pagePoolRegistry = BrowserPagePoolRegistry(primary: pages)
        self.systemNowPlaying = systemNowPlaying
        self.startupBehavior = startupBehavior
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
        Window(
            ProductIdentity.name,
            id: presentsInstalledApplicationUI
                ? BrowserSceneID.browser.rawValue
                : "crest-xctest-host"
        ) {
            if presentsInstalledApplicationUI {
                Group {
                    if onboardingProgress.isLaunchGateActive {
                        BrowserMacOnboardingLaunchGate(
                            coordinator: onboardingCoordinator
                        )
                    } else {
                        BrowserMacWindowScene(
                            id: .main,
                            browser: browser,
                            pages: pages,
                            chrome: chrome,
                            transientBrowsing: transientBrowsing,
                            windowState: mainWindowState,
                            extensionControllerPool: extensionControllerPool,
                            pagePoolRegistry: pagePoolRegistry,
                            spaceAccess: spaceAccess,
                            spaceSettingsPresentation: spaceSettingsPresentation,
                            startupBehavior: startupBehavior,
                            shortcuts: shortcuts,
                            sidebarWidgets: sidebarWidgets
                        )
                        .environment(windowTransparency)
                        .environment(splitFocus)
                        .environment(
                            \.browserSidebarWidgetRuntime,
                            sidebarWidgets
                        )
                    }
                }
                .background(
                    BrowserSoftwareUpdateWindowPresenter(
                        model: softwareUpdates.model
                    )
                )
                .task { await cloudSync.start() }
            } else {
                EmptyView()
            }
        }
        .defaultSize(
            width: BrowserMainWindowSizingPolicy.idealContentSize.width,
            height: BrowserMainWindowSizingPolicy.idealContentSize.height
        )
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .handlesExternalEvents(
            matching: BrowserExternalLinkScenePolicy.primarySceneActivation
        )
        .commands {
            BrowserCommands(
                browser: browser,
                pages: pages,
                chrome: chrome,
                shortcuts: shortcuts,
                softwareUpdates: softwareUpdates
            )
        }

        WindowGroup(
            "Quick Window",
            id: BrowserSceneID.quickWindow.rawValue,
            for: BrowserQuickWindowRequest.self
        ) { $request in
            if presentsInstalledApplicationUI {
                BrowserQuickWindowScene(
                    request: $request,
                    browser: browser,
                    pages: pages,
                    spaceAccess: spaceAccess,
                    pagePoolRegistry: pagePoolRegistry
                )
                .environment(windowTransparency)
                .frame(
                    minWidth: BrowserQuickWindowLayout.minimumWidth,
                    minHeight: BrowserQuickWindowLayout.minimumHeight
                )
            } else {
                EmptyView()
            }
        }
        .windowIdealPlacement { _, context in
            let frame =
                BrowserTransientWindowGeometryPolicy.centeredContentFrame(
                    in: context.defaultDisplay.visibleRect
                )
            return WindowPlacement(
                x: frame.minX,
                y: frame.minY,
                width: frame.width,
                height: frame.height
            )
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .handlesExternalEvents(
            matching: BrowserExternalLinkScenePolicy.quickWindowSceneActivation
        )
        // A quick window answers one lookup and is done with it, so it belongs
        // to the session that asked for it rather than to the next launch.
        .restorationBehavior(.disabled)

        Window("Private Browsing", id: BrowserSceneID.privateBrowser.rawValue) {
            if presentsInstalledApplicationUI {
                BrowserRootView(
                    browser: privateBrowser,
                    pages: privatePages,
                    chrome: privateChrome,
                    transientBrowsing: privateTransientBrowsing,
                    startupBehavior: .lastActiveTab,
                    shortcuts: shortcuts
                )
                .environment(windowTransparency)
                .environment(splitFocus)
                .environment(
                    \.browserSidebarWidgetRuntime,
                    sidebarWidgets
                )
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(.dark)
                .onDisappear(perform: closePrivateBrowsingWindow)
            } else {
                EmptyView()
            }
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        // Private browsing that reopened itself on the next launch would be a
        // promise broken: the mode exists so that closing the window ends it.
        .restorationBehavior(.disabled)

        Window("Crest Settings", id: BrowserSceneID.settings.rawValue) {
            if presentsInstalledApplicationUI {
                BrowserSettingsView(
                    browser: browser,
                    pages: pages,
                    cloudSync: cloudSync,
                    spaceAccess: spaceAccess,
                    dataDeleter: pagePoolRegistry,
                    shortcuts: shortcuts,
                    onboardingCoordinator: onboardingCoordinator,
                    spaceSettingsPresentation: spaceSettingsPresentation
                )
                .environment(windowTransparency)
                .environment(splitFocus)
                .environment(softwareUpdates)
                // Scoped to this window rather than to the app: a browser window's
                // controls belong to whichever Space owns them and must keep that
                // Space's accent, while Settings is Crest speaking for itself and
                // has no business rendering system blue.
                .tint(CrestBrandTheme.accent)
                .task { await cloudSync.start() }
            } else {
                EmptyView()
            }
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(
            width: BrowserSettingsChromePolicy.defaultContentSize.width,
            height: BrowserSettingsChromePolicy.defaultContentSize.height
        )
        .windowResizability(.contentMinSize)
        // Settings is opened on purpose, so it opens when it is asked for and
        // not because it happened to be on screen when Crest last quit.
        .restorationBehavior(.disabled)

        Window(
            "Software Update",
            id: BrowserSceneID.softwareUpdate.rawValue
        ) {
            if presentsInstalledApplicationUI {
                BrowserSoftwareUpdateView(model: softwareUpdates.model)
                    .tint(CrestBrandTheme.accent)
            } else {
                EmptyView()
            }
        }
        .defaultSize(width: 620, height: 440)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)

        Window("Crest Setup", id: BrowserOnboardingCoordinator.sceneID) {
            if presentsInstalledApplicationUI {
                BrowserOnboardingWindow(
                    request: onboardingCoordinator.request,
                    browser: browser,
                    cloudSync: cloudSync,
                    progress: onboardingProgress
                )
                .task { await cloudSync.start() }
            } else {
                EmptyView()
            }
        }
        .defaultSize(width: 1180, height: 820)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        // Setup is opened by the launch gate on a first run and by Settings on
        // request. Restoring it instead would reopen a finished wizard over the
        // browser on every launch after the one that ran it — a window nothing
        // asked for, standing in front of everything the sidebar needs to hit.
        .restorationBehavior(.disabled)
    }

    private func closePrivateBrowsingWindow() {
        let closingSession = privateBrowser.session
        privatePages.closePrivateBrowsingSession(closingSession)
        privateBrowser.resetPrivateBrowsingSession()
        privateChrome.dismissCommandPalette()
        privateTransientBrowsing.dismissPeek()
    }

}
