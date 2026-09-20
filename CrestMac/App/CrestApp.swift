import SwiftUI

#if !CREST_CHROMIUM_HOST
@main
#endif
struct CrestApp: App {
    @State private var application = BrowserMacApplication()

    private var browser: BrowserStore { application.browser }
    private var cloudSync: BrowserCloudSyncController { application.cloudSync }
    private var onboardingProgress: BrowserOnboardingProgressStore { application.onboardingProgress }
    private var onboardingCoordinator: BrowserOnboardingCoordinator { application.onboardingCoordinator }
    private var pages: BrowserPagePool { application.pages }
    private var chrome: BrowserChromeState { application.chrome }
    private var transientBrowsing: BrowserTransientBrowsingCoordinator { application.transientBrowsing }
    private var windowCoordinator: BrowserMacWindowCoordinator { application.windowCoordinator }
    private var privateBrowser: BrowserStore { application.privateBrowser }
    private var privatePages: BrowserPagePool { application.privatePages }
    private var privateChrome: BrowserChromeState { application.privateChrome }
    private var privateTransientBrowsing: BrowserTransientBrowsingCoordinator { application.privateTransientBrowsing }
    private var spaceAccess: BrowserSpaceAccessController { application.spaceAccess }
    private var shortcuts: BrowserShortcutStore { application.shortcuts }
    private var spaceSettingsPresentation: BrowserSpaceSettingsPresentationState { application.spaceSettingsPresentation }
    private var windowTransparency: BrowserWindowTransparencyStore { application.windowTransparency }
    private var splitFocus: BrowserSplitFocusPreferenceStore { application.splitFocus }
    private var softwareUpdates: BrowserSoftwareUpdateService { application.softwareUpdates }
    private var sidebarWidgets: BrowserSidebarWidgetRuntime { application.sidebarWidgets }
    private var pagePoolRegistry: BrowserPagePoolRegistry { application.pagePoolRegistry }
    private var systemNowPlaying: BrowserSystemNowPlayingCoordinator? { application.systemNowPlaying }
    private var startupBehavior: BrowserStartupBehavior { application.startupBehavior }
    private var presentsInstalledApplicationUI: Bool { application.presentsInstalledApplicationUI }

    var body: some Scene {
        WindowGroup(
            ProductIdentity.name,
            id: presentsInstalledApplicationUI
                ? BrowserSceneID.browser.rawValue
                : "crest-xctest-host",
            for: BrowserMacWindowRequest.self
        ) { $request in
            if presentsInstalledApplicationUI {
                Group {
                    if onboardingProgress.isLaunchGateActive {
                        BrowserMacOnboardingLaunchGate(
                            coordinator: onboardingCoordinator
                        )
                    } else {
                        application.browserWindowContent(request ?? .initial)
                    }
                }
                .task {
                    BrowserMacAppIconPreference.restore()
                    await cloudSync.start()
                }
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
                softwareUpdates: softwareUpdates,
                spaceAccess: spaceAccess
            )
        }

        WindowGroup(ProductIdentity.name, id: BrowserSceneID.blankWindow.rawValue, for: BrowserMacWindowRequest.self) {
            $request in
            if presentsInstalledApplicationUI, let request {
                application.browserWindowContent(request)
            }
        }
        .defaultSize(
            width: BrowserMainWindowSizingPolicy.idealContentSize.width,
            height: BrowserMainWindowSizingPolicy.idealContentSize.height
        )
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .restorationBehavior(.disabled)

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
                    pagePoolRegistry: pagePoolRegistry,
                    windowCoordinator: windowCoordinator
                )
                .modifier(BrowserChromeAppearancePersistence())
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
                application.privateWindowContent
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

        Window(
            "What's New in Crest",
            id: BrowserSceneID.softwareUpdateDetails.rawValue
        ) {
            if presentsInstalledApplicationUI {
                BrowserSoftwareUpdateDetailsView(model: softwareUpdates.model)
                    .tint(CrestBrandTheme.accent)
            } else {
                EmptyView()
            }
        }
        .defaultSize(width: 620, height: 520)
        .windowResizability(.contentMinSize)
        // Release notes are opened from the update card on purpose; restoring
        // them would recreate the same unsolicited window this scene replaces.
        .restorationBehavior(.disabled)

        Window("Crest Setup", id: BrowserOnboardingCoordinator.sceneID) {
            if presentsInstalledApplicationUI {
                BrowserOnboardingWindow(
                    request: onboardingCoordinator.request,
                    browser: browser,
                    cloudSync: cloudSync,
                    progress: onboardingProgress,
                    spaceAccess: spaceAccess
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

}
