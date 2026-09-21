import SwiftUI

#if !CREST_CHROMIUM_HOST
@main
#endif
struct CrestApp: App {
    @State private var launch = BrowserApplicationLaunch { try BrowserMacApplication() }

    var body: some Scene {
        WindowGroup(
            ProductIdentity.name,
            id: (launch.value?.presentsInstalledApplicationUI ?? true)
                ? BrowserSceneID.browser.rawValue
                : "crest-xctest-host",
            for: BrowserMacWindowRequest.self
        ) { $request in
            if let application = launch.value, application.presentsInstalledApplicationUI {
                Group {
                    if application.onboardingProgress.isLaunchGateActive {
                        BrowserMacOnboardingLaunchGate(
                            coordinator: application.onboardingCoordinator
                        )
                    } else {
                        application.browserWindowContent(request ?? .initial)
                    }
                }
                .task {
                    BrowserMacAppIconPreference.restore()
                    await application.cloudSync.start()
                }
            } else if launch.failure != nil {
                BrowserSessionRecoveryView(launch: launch)
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
            if let application = launch.value {
                BrowserCommands(
                    browser: application.browser,
                    pages: application.pages,
                    chrome: application.chrome,
                    shortcuts: application.shortcuts,
                    softwareUpdates: application.softwareUpdates,
                    spaceAccess: application.spaceAccess
                )
            }
        }

        WindowGroup(ProductIdentity.name, id: BrowserSceneID.blankWindow.rawValue, for: BrowserMacWindowRequest.self) {
            $request in
            if let application = launch.value, application.presentsInstalledApplicationUI, let request {
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
            if let application = launch.value, application.presentsInstalledApplicationUI {
                BrowserQuickWindowScene(
                    request: $request,
                    browser: application.browser,
                    pages: application.pages,
                    spaceAccess: application.spaceAccess,
                    pagePoolRegistry: application.pagePoolRegistry,
                    windowCoordinator: application.windowCoordinator
                )
                .modifier(BrowserChromeAppearancePersistence())
                .environment(application.windowTransparency)
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
            if let application = launch.value, application.presentsInstalledApplicationUI {
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
            if let application = launch.value, application.presentsInstalledApplicationUI {
                BrowserSoftwareUpdateDetailsView(model: application.softwareUpdates.model)
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
            if let application = launch.value, application.presentsInstalledApplicationUI {
                BrowserOnboardingWindow(
                    request: application.onboardingCoordinator.request,
                    browser: application.browser,
                    cloudSync: application.cloudSync,
                    progress: application.onboardingProgress,
                    spaceAccess: application.spaceAccess
                )
                .task { await application.cloudSync.start() }
            } else {
                EmptyView()
            }
        }
        .defaultSize(width: 1180, height: 820)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        // Setup is opened by the launch gate on a first run and by Settings on
        // request. Restoring it instead would reopen a finished wizard over the
        // application.browser on every launch after the one that ran it — a window nothing
        // asked for, standing in front of everything the sidebar needs to hit.
        .restorationBehavior(.disabled)
    }

}
