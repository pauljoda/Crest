import Foundation
import Observation

@Observable
@MainActor
final class MobileBrowserWindowSceneModel {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let navigation: MobileBrowserNavigationState
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let privateBrowser: BrowserStore
    let privatePages: MobileBrowserPageStore
    let privateNavigation: MobileBrowserNavigationState
    let privateTransientBrowsing: BrowserTransientBrowsingCoordinator
    let windowState: BrowserWindowStateStore
    let pageStoreRegistry: MobileBrowserPageStoreRegistry
    let spaceAccess: BrowserSpaceAccessController
    let startupBehavior: BrowserStartupBehavior

    @ObservationIgnored private let linkPreferenceStore: BrowserLinkPreferenceStore

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
        usesEphemeralWebsiteDataStores: Bool = false,
        mediaSessionStore: BrowserMediaSessionStore? = nil,
        linkPreferenceStore: BrowserLinkPreferenceStore = .shared
    ) {
        let windowState = BrowserWindowStateStore(
            id: id,
            session: rootBrowser.session,
            persistence: windowStatePersistence
        )
        let browser = rootBrowser.makeWindowStore(restoring: windowState.state)
        let sidebarIsPresented = windowState.sidebarIsPresented ?? true
        let navigation = MobileBrowserNavigationState(
            regularSidebarIsPresented: sidebarIsPresented,
            initiallyShowsCompactPage: startupBehavior.activatesRestoredTab
        )
        let transientBrowsing = BrowserTransientBrowsingCoordinator()
        let pages = MobileBrowserPageStore(
            // The window's own store is where a tab's web view actually lives, so
            // this is the residency a squeeze has to reach.
            monitorsMemoryPressure: monitorsMemoryPressure,
            usesEphemeralWebsiteDataStores: usesEphemeralWebsiteDataStores,
            permissionCenter: permissionCenter,
            mediaSessionStore: mediaSessionStore,
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
        let privateBrowser = BrowserStore.privateBrowsing()
        let privateNavigation = MobileBrowserNavigationState(
            regularSidebarIsPresented: sidebarIsPresented
        )
        let privateTransientBrowsing = BrowserTransientBrowsingCoordinator()
        let privatePages = MobileBrowserPageStore(
            browsingMode: .privateBrowsing,
            permissionCenter: BrowserSitePermissionCenter(),
            // The private store answers to the private session, so a popup from a
            // private page can only ever land in a private tab.
            popupTabHost: privateBrowser.popupTabHost,
            openNewTab: { url in privateBrowser.openNewTab(url: url) },
            openModifiedLink: { url, spaceID, selecting in
                privateBrowser.openNewTab(url: url, in: spaceID, selecting: selecting)
            },
            openPeek: { request in
                privateTransientBrowsing.presentPeek(request)
            },
            stagePeek: { request in
                privateTransientBrowsing.stagePeek(request)
            },
            commitPeek: { request in
                privateTransientBrowsing.commitPeek(request)
            },
            cancelStagedPeek: { id in
                privateTransientBrowsing.cancelStagedPeek(id: id)
            }
        )

        self.browser = browser
        self.navigation = navigation
        self.pages = pages
        self.transientBrowsing = transientBrowsing
        self.privateBrowser = privateBrowser
        self.privateNavigation = privateNavigation
        self.privatePages = privatePages
        self.privateTransientBrowsing = privateTransientBrowsing
        self.windowState = windowState
        self.pageStoreRegistry = pageStoreRegistry
        self.spaceAccess = spaceAccess
        self.startupBehavior = startupBehavior
        self.linkPreferenceStore = linkPreferenceStore
    }

    func activateWindow() {
        pageStoreRegistry.register(pages)
    }

    func cleanupDeferredWebsiteDataStores() async {
        await BrowserDeferredWebsiteDataStoreCleanup.cleanupPendingStores()
    }

    func sweepExpiredTabsWhileActive() async {
        await browser.sweepExpiredBrowsingDataWhileSceneIsActive {
            pages.downloadCenter.sweepExpiredRecords(using: browser.session)
        }
    }

    func handleMemoryPressure() {
        pages.handleMemoryPressure(.critical)
        privatePages.handleMemoryPressure(.critical)
    }

    func captureWindowSelection() {
        windowState.captureSelection(from: browser.session)
    }

    func prepareForInactiveScene() {
        spaceAccess.lockAllForInactiveScene()
        flushPendingPersistence()
    }

    func prepareForBackgroundScene() {
        spaceAccess.lockAll()
        flushPendingPersistence()
    }

    func closeWindowRuntime() {
        pages.downloadRiskConfirmation.cancelAll()
        privatePages.downloadRiskConfirmation.cancelAll()
        pageStoreRegistry.unregister(pages)
        flushPendingPersistence()
    }

    func togglePrivateBrowsing(from mode: BrowserBrowsingMode) -> BrowserBrowsingMode {
        if mode.isPrivate {
            privatePages.downloadRiskConfirmation.cancelAll()
            synchronizeSidebarPresentation(navigation)
            return .standard
        }

        synchronizeSidebarPresentation(privateNavigation)
        privateNavigation.selectTab()
        return .privateBrowsing
    }

    func closePrivateBrowsing() -> BrowserBrowsingMode {
        let closingSession = privateBrowser.session
        privatePages.downloadRiskConfirmation.cancelAll()
        privatePages.closePrivateBrowsingSession(closingSession)
        privateBrowser.resetPrivateBrowsingSession()
        privateNavigation.showTabViewer()
        privateTransientBrowsing.dismissPeek()
        synchronizeSidebarPresentation(navigation)
        return .standard
    }

    @discardableResult
    func routeExternalURL(_ url: URL) async -> Bool {
        let decision = linkPreferenceStore.routingDecision(
            for: url,
            in: browser.session,
            unavailableSpaceIDs: browser.deletingSpaceIDs
        )
        guard
            let route = MobileBrowserWindowSceneRoute.resolve(
                url: url,
                decision: decision,
                session: browser.session
            ),
            let space = browser.session.space(id: route.spaceID),
            await spaceAccess.unlock(space)
        else { return false }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard browser.space(matching: assignment) != nil else { return false }

        switch route {
        case .quickWindow(let url, let spaceID):
            guard spaceID == assignment.spaceID else { return false }
            transientBrowsing.presentQuickWindow(
                BrowserQuickWindowRequest(
                    url: url,
                    spaceAssignment: assignment
                )
            )
        case .space(let url, let spaceID):
            guard spaceID == assignment.spaceID,
                browser.openNewTab(
                    url: url,
                    matching: assignment
                ) != nil
            else {
                return false
            }
            pages.select(session: browser.session)
            pages.load(url)
            navigation.selectTab()
        }
        return true
    }

    private func flushPendingPersistence() {
        // Reading resident WebKit session state must happen while pages remain
        // resident, before the asynchronous persistence flush begins.
        pages.archiveResidentTabStates()
        Task {
            await browser.flushPendingSyncPersistence()
            await windowState.flushPendingPersistence()
            await pages.flushPendingTabStateWrites()
        }
    }

    private func synchronizeSidebarPresentation(
        _ navigation: MobileBrowserNavigationState
    ) {
        if windowState.sidebarIsPresented ?? true {
            navigation.dockRegularSidebar()
            return
        }
        navigation.hideRegularSidebar()
    }
}
