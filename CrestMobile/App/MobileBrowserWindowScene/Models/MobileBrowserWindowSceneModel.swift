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
        windowLayouts: BrowserWindowLayouts,
        startupBehavior: BrowserStartupBehavior,
        monitorsMemoryPressure: Bool,
        usesEphemeralWebsiteDataStores: Bool = false,
        mediaSessionStore: BrowserMediaSessionStore? = nil,
        downloads: MobileBrowserDownloads? = nil,
        privateDownloads: MobileBrowserDownloads? = nil,
        linkPreferenceStore: BrowserLinkPreferenceStore = .shared
    ) {
        // A scene restores the Space it showed and starts without a tab.
        let browser = rootBrowser.makeWindowStore(BrowserWindowOpening(id: id, saved: true, restoresTabs: false))
        let windowState = BrowserWindowStateStore(id: id, browser: browser, layouts: windowLayouts)
        let sidebarIsPresented = windowState.sidebarIsPresented ?? true
        let navigation = MobileBrowserNavigationState(
            regularSidebarIsPresented: sidebarIsPresented,
            initiallyShowsCompactPage: !sidebarIsPresented
        )
        let transientBrowsing = BrowserTransientBrowsingCoordinator()
        let pages = MobileBrowserPageStore(
            browser: browser,
            // The window's own store is where a tab's web view actually lives, so
            // this is the residency a squeeze has to reach.
            monitorsMemoryPressure: monitorsMemoryPressure,
            usesEphemeralWebsiteDataStores: usesEphemeralWebsiteDataStores,
            permissionCenter: permissionCenter,
            mediaSessionStore: mediaSessionStore,
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
            openPeek: { request in transientBrowsing.presentPeek(request) }
        )
        let privateBrowser = BrowserStore.privateBrowsing(core: rootBrowser.core)
        let privateNavigation = MobileBrowserNavigationState(
            regularSidebarIsPresented: sidebarIsPresented
        )
        let privateTransientBrowsing = BrowserTransientBrowsingCoordinator()
        let privatePages = MobileBrowserPageStore(
            browser: privateBrowser,
            browsingMode: .privateBrowsing,
            permissionCenter: privateDownloads?.center.permissionCenter ?? BrowserSitePermissionCenter(),
            downloads: privateDownloads,
            // The private store answers to the private session, so a popup from a
            // private page can only ever land in a private tab.
            popupTabHost: privateBrowser.popupTabHost,
            linkDestinationHost: BrowserLinkDestinationHost(browser: privateBrowser, spaceAccess: spaceAccess),
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
                return BrowserModifiedLinkRegistration(tab: tab, space: space, session: privateBrowser.presented)
            },
            openPeek: { request in
                privateTransientBrowsing.presentPeek(request)
            }
        )

        browser.tabLinkProvider = pages
        privateBrowser.tabLinkProvider = privatePages
        browser.tabCopying = pages
        privateBrowser.tabCopying = privatePages
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

    @discardableResult
    func presentGettingStartedAfterSetup(matching assignment: BrowserTabRuntimeAssignment) -> Bool {
        guard
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(spaceID: assignment.spaceID, profileID: assignment.profileID),
                in: browser, accessController: spaceAccess),
            browser.session.spaces.first?.id == space.id,
            browser.selectedTabID(in: space.id) == assignment.tabID,
            space.tabs.first(where: { $0.id == assignment.tabID })?.nativeContent == .gettingStarted
        else { return false }
        pages.select(session: browser.presented)
        navigation.presentSelectedTabAfterSetup()
        return true
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

    func prepareForInactiveScene() {
        spaceAccess.lockAllForInactiveScene()
        flushPendingPersistence()
    }

    func prepareForBackgroundScene() {
        spaceAccess.lockAll()
        flushPendingPersistence()
    }

    func closeWindowRuntime() {
        // Other windows still present the standard confirmations they share.
        cancelPrivateDownloadConfirmations()
        // This window's private session closes with it, and so do its private
        // downloads and their records in the shared private center.
        for space in privateBrowser.session.spaces {
            privatePages.downloadCenter.deleteRecords(profileID: space.profile.id, spaceID: space.id)
        }
        pageStoreRegistry.unregister(pages)
        flushPendingPersistence()
    }

    func togglePrivateBrowsing(from mode: BrowserBrowsingMode) -> BrowserBrowsingMode {
        if mode.isPrivate {
            cancelPrivateDownloadConfirmations()
            synchronizeSidebarPresentation(navigation)
            return .standard
        }

        synchronizeSidebarPresentation(privateNavigation)
        privateNavigation.selectTab()
        return .privateBrowsing
    }

    func closePrivateBrowsing() -> BrowserBrowsingMode {
        let closingSession = privateBrowser.session
        cancelPrivateDownloadConfirmations()
        privatePages.closePrivateBrowsingSession(closingSession)
        privateBrowser.resetPrivateBrowsingSession()
        privateNavigation.showTabViewer()
        privateTransientBrowsing.dismissPeek()
        synchronizeSidebarPresentation(navigation)
        return .standard
    }

    @discardableResult
    func routeExternalURL(_ url: URL) async -> Bool {
        guard
            let decision = linkPreferenceStore.routingDecision(
                for: url,
                in: browser.presented,
                unavailableSpaceIDs: browser.deletingSpaceIDs,
                asking: browser.core
            ),
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
            pages.selectAndLoad(url, in: browser.presented)
            navigation.selectTab()
        }
        return true
    }

    /// Private downloads share one confirmation across windows; this window
    /// cancels only its own private profile's requests.
    private func cancelPrivateDownloadConfirmations() {
        privatePages.downloadRiskConfirmation.cancelAll(
            profileIDs: Set(privateBrowser.session.spaces.map(\.profile.id)))
    }

    private func flushPendingPersistence() {
        // Reading resident WebKit session state must happen while pages remain
        // resident, before the asynchronous persistence flush begins.
        pages.archiveResidentTabStates()
        // iOS may suspend the app once the scene leaves the foreground and end
        // it while suspended, so the flush keeps it running until it is done.
        let backgroundTask = MobileBackgroundTask(named: "Save pending edits")
        Task { [browser, pages] in
            await BrowserPersistenceFlush().run {
                await browser.flushPendingSyncPersistenceUntilSettled()
                await pages.flushPendingTabStateWrites()
            }
            backgroundTask.end()
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
