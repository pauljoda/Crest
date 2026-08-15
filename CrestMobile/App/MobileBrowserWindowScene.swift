import SwiftUI
import UIKit

struct MobileBrowserWindowScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(BrowserCloudSyncController.self) private var cloudSync

    private let onboardingProgress: BrowserOnboardingProgressStore
    private let automaticallyPresentsOnboarding: Bool
    @Bindable private var onboardingCoordinator: BrowserOnboardingCoordinator

    @State private var model: MobileBrowserWindowSceneModel
    @State private var browsingMode: BrowserBrowsingMode = .standard
    @State private var hasPresentedAutomaticOnboarding = false

    init(
        id: BrowserWindowID,
        rootBrowser: BrowserStore,
        permissionCenter: BrowserSitePermissionCenter,
        pageStoreRegistry: MobileBrowserPageStoreRegistry,
        spaceAccess: BrowserSpaceAccessController,
        tabStateArchive: (any BrowserTabStateArchiving)?,
        windowStatePersistence: any BrowserWindowStatePersisting,
        startupBehavior: BrowserStartupBehavior,
        monitorsMemoryPressure: Bool,
        usesEphemeralWebsiteDataStores: Bool,
        onboardingProgress: BrowserOnboardingProgressStore,
        onboardingCoordinator: BrowserOnboardingCoordinator,
        automaticallyPresentsOnboarding: Bool
    ) {
        self.onboardingProgress = onboardingProgress
        self.onboardingCoordinator = onboardingCoordinator
        self.automaticallyPresentsOnboarding = automaticallyPresentsOnboarding
        _model = State(
            initialValue: MobileBrowserWindowSceneModel(
                id: id,
                rootBrowser: rootBrowser,
                permissionCenter: permissionCenter,
                pageStoreRegistry: pageStoreRegistry,
                spaceAccess: spaceAccess,
                tabStateArchive: tabStateArchive,
                windowStatePersistence: windowStatePersistence,
                startupBehavior: startupBehavior,
                monitorsMemoryPressure: monitorsMemoryPressure,
                usesEphemeralWebsiteDataStores: usesEphemeralWebsiteDataStores
            )
        )
    }

    var body: some View {
        sceneSurface
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(
                BrowserWindowAccessibilityID.scene(model.windowState.id)
            )
            .task {
                await model.cleanupDeferredWebsiteDataStores()
            }
            // Tab cleanup follows the scene: it sweeps as soon as the scene becomes
            // active and then keeps sweeping on a low-frequency tick, and SwiftUI
            // cancels the loop whenever the phase changes so a backgrounded scene
            // stops sweeping. Private browsing is left alone; those Spaces never clean
            // up, and the session goes away with the mode.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await model.sweepExpiredTabsWhileActive()
            }
            .onAppear(perform: model.activateWindow)
            .onDisappear(perform: model.closeWindowRuntime)
            .onOpenURL(perform: openExternalURL)
            // UIKit's warning supplements the kernel pressure source the standard store
            // watches: it only reaches a foregrounded app, but it is also the one signal
            // the private store gets, since private pages have no archive to come back
            // from. Both signals land on the same handler, which collapses the pair that
            // one squeeze produces into a single trim.
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didReceiveMemoryWarningNotification
                )
            ) { _ in
                model.handleMemoryPressure()
            }
            .onChange(
                of: BrowserWindowState(
                    id: model.windowState.id,
                    restoring: model.browser.session
                )
            ) {
                model.captureWindowSelection()
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .active:
                    model.activateWindow()
                case .inactive:
                    model.prepareForInactiveScene()
                case .background:
                    model.prepareForBackgroundScene()
                @unknown default:
                    model.prepareForBackgroundScene()
                }
            }
            .animation(
                BrowserVisualAccessibilityPolicy.animation(
                    CrestMotion.onboardingPresentation,
                    reduceMotion: reduceMotion
                ),
                value: onboardingCoordinator.isMobilePresented
            )
            .onAppear(perform: presentAutomaticOnboardingIfNeeded)
    }

    @ViewBuilder
    private var sceneSurface: some View {
        if showsAutomaticLaunchGate {
            onboardingSurface
        } else {
            browserSurfaceWithOnboardingOverlay
        }
    }

    private var browserSurfaceWithOnboardingOverlay: some View {
        ZStack {
            browserSurface
                .allowsHitTesting(!onboardingCoordinator.isMobilePresented)
                .accessibilityHidden(onboardingCoordinator.isMobilePresented)

            if onboardingCoordinator.isMobilePresented {
                onboardingSurface
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .zIndex(10)
            }
        }
    }

    @ViewBuilder
    private var browserSurface: some View {
        if browsingMode.isPrivate {
            MobileBrowserRootView(
                browser: model.privateBrowser,
                pages: model.privatePages,
                dataDeleter: model.privatePages,
                navigation: model.privateNavigation,
                transientBrowsing: model.privateTransientBrowsing,
                windowState: model.windowState,
                suspendsCompactPagePresentation: onboardingCoordinator.isMobilePresented,
                startupBehavior: .lastActiveTab,
                togglePrivateBrowsing: togglePrivateBrowsing,
                closePrivateBrowsing: closePrivateBrowsing
            )
            .preferredColorScheme(.dark)
        } else {
            MobileBrowserRootView(
                browser: model.browser,
                pages: model.pages,
                dataDeleter: model.pageStoreRegistry,
                navigation: model.navigation,
                transientBrowsing: model.transientBrowsing,
                spaceAccess: model.spaceAccess,
                windowState: model.windowState,
                suspendsCompactPagePresentation: onboardingCoordinator.isMobilePresented,
                startupBehavior: model.startupBehavior,
                togglePrivateBrowsing: togglePrivateBrowsing,
                closePrivateBrowsing: closePrivateBrowsing
            )
        }
    }

    private var onboardingSurface: some View {
        MobileBrowserOnboardingView(
            request: onboardingCoordinator.request,
            browser: model.browser,
            cloudSync: cloudSync,
            progress: onboardingProgress,
            coordinator: onboardingCoordinator
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var showsAutomaticLaunchGate: Bool {
        let gateIsActive =
            onboardingProgress.isLaunchGateActive
            && onboardingCoordinator.request.entryPoint == .firstRun
        return MobileBrowserAutomaticOnboardingPolicy.showsLaunchGate(
            automaticallyPresentsOnboarding: automaticallyPresentsOnboarding,
            isLaunchGateActive: gateIsActive
        )
    }

    private func presentAutomaticOnboardingIfNeeded() {
        guard onboardingProgress.shouldPresentWelcome,
            automaticallyPresentsOnboarding,
            !hasPresentedAutomaticOnboarding
        else { return }
        onboardingCoordinator.presentOnMobile(.firstRun)
        hasPresentedAutomaticOnboarding = true
    }

    private func togglePrivateBrowsing() {
        let destinationMode = model.togglePrivateBrowsing(from: browsingMode)
        withAnimation(modeAnimation) {
            browsingMode = destinationMode
        }
    }

    private func closePrivateBrowsing() {
        let destinationMode = model.closePrivateBrowsing()
        withAnimation(modeAnimation) {
            browsingMode = destinationMode
        }
    }

    private func openExternalURL(_ url: URL) {
        Task {
            guard await model.routeExternalURL(url) else { return }
            withAnimation(modeAnimation) {
                browsingMode = .standard
            }
        }
    }

    private var modeAnimation: Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            CrestMotion.navigation,
            reduceMotion: reduceMotion
        )
    }
}
