import AppKit
import Dispatch
import Foundation
import Observation
import WebKit
import os

struct BrowserModifiedLinkRegistration {
    let tab: BrowserTab
    let space: BrowserSpace
    let session: BrowserSession
}

struct BrowserBackgroundPageUpdate {
    let tabID: TabID
    let assignment: BrowserSpaceRuntimeAssignment
    let url: URL?
    let title: String
    let faviconData: Data?
    let iconAccent: BrowserTabIconAccent?
    let estimatedProgress: Double
    let isLoading: Bool
    let readerModeState: BrowserReaderModeState
    let completedNavigationURL: URL?
    let processTerminationCount: Int
}

@MainActor
private struct BrowserBackgroundPageSnapshot: Equatable {
    let url: URL?
    let title: String
    let faviconData: Data?
    let iconAccent: BrowserTabIconAccent?
    let estimatedProgress: Double
    let isLoading: Bool
    let readerModeState: BrowserReaderModeState
    let completedNavigationCount: Int
    let processTerminationCount: Int
    let hasNavigationFailure: Bool

    init(page: BrowserPage) {
        url = page.displayURL
        title = page.navigationFailure?.displayHost ?? page.title
        faviconData = page.faviconData
        iconAccent = page.siteThemeIconAccent
        estimatedProgress = page.estimatedProgress
        isLoading = page.isLoading
        readerModeState = page.readerModeState
        completedNavigationCount = page.completedNavigationCount
        processTerminationCount = page.processTerminationCount
        hasNavigationFailure = page.navigationFailure != nil
    }
}

@Observable
@MainActor
final class BrowserPagePool:
    BrowserSpaceDataDeleting,
    BrowserPageHosting,
    BrowserDefaultPageZoomObserving
{
    private struct ExtensionOffscreenDocumentKey: Hashable {
        let spaceID: SpaceID
        let extensionBaseURL: URL
    }

    @ObservationIgnored private static let lifecycleSignposter = OSSignposter(
        subsystem: "com.pauldavis.crest",
        category: "WebKitLifecycle"
    )

    typealias HTTPAuthenticationCredentialLoader =
        @MainActor (
            BrowserHTTPAuthenticationProtectionSpace,
            SpaceID
        ) async throws -> BrowserCredential?

    typealias HTTPAuthenticationCredentialSaver =
        @MainActor (
            BrowserHTTPAuthenticationSaveRequest,
            SpaceID
        ) async throws -> Void

    typealias ResidencyDecisionProvider =
        @MainActor (BrowserPage, Bool) async -> BrowserPageResidencyDecision

    typealias ModifiedLinkOpener =
        @MainActor (URL, SpaceID, Bool) -> BrowserModifiedLinkRegistration?

    typealias BackgroundPageUpdateHandler =
        @MainActor (BrowserBackgroundPageUpdate) -> BrowserSession?

    /// The focused card: the one tab the URL bar, navigation controls, find,
    /// zoom, sharing, and every lifecycle observer speak for. Split View adds
    /// cards beside it without adding a second focus.
    private(set) var activeTabID: TabID?

    /// Every card the content area is presenting, in session member order.
    ///
    /// Derived from `BrowserSpace.presentedSplitMembers(for:)` — the same
    /// source the sidebar folds its group row from, so the two can never
    /// disagree about who is on screen. A tab outside a renderable split
    /// presents alone, which is one element rather than a special case, and
    /// `activeTabID` is always a member while anything is presented.
    ///
    /// Deliberately observable: a card mount reads it through
    /// `presentedPage(for:)` and has to re-render when membership changes.
    private(set) var presentedTabIDs: [TabID] = []
    private(set) var residencyRevision = 0
    private(set) var contentBlockingErrorDescription: String?
    let downloadCenter: BrowserDownloadCenter
    let extensionControllerPool: BrowserExtensionControllerPool
    @ObservationIgnored private let extensionWebpageMenuProvider: BrowserExtensionWebpageMenuProvider
    let permissionCenter: BrowserSitePermissionCenter
    let serverTrustOverrides = BrowserServerTrustOverrideStore()

    @ObservationIgnored private var pages: [TabID: BrowserPage] = [:]
    /// Alternate WebKit runtimes retained while a tab crosses between ordinary
    /// web content and extension origins. A configuration cannot be changed
    /// after a `WKWebView` is created, and keeping the prior page alive avoids
    /// discarding forms, media, and other in-page state during the swap.
    @ObservationIgnored private var suspendedPagesByTabID: [TabID: [BrowserPage]] = [:]
    /// WebKit cannot share a back/forward list between ordinary and extension
    /// configurations. These two links make the configuration boundary behave
    /// like one tab-level history entry in each direction.
    @ObservationIgnored private var runtimeBackPagesByTabID: [TabID: BrowserPage] = [:]
    @ObservationIgnored private var runtimeForwardPagesByTabID: [TabID: BrowserPage] = [:]
    @ObservationIgnored private var inactiveSinceByTabID: [TabID: Date] = [:]
    @ObservationIgnored private var ephemeralDataStores: [UUID: WKWebsiteDataStore] = [:]
    @ObservationIgnored private let residencyDecisionProvider: ResidencyDecisionProvider
    @ObservationIgnored private var memoryPressureReleaseTask: Task<Void, Never>?
    @ObservationIgnored private let browsingMode: BrowserBrowsingMode
    @ObservationIgnored private let usesEphemeralWebsiteDataStores: Bool
    @ObservationIgnored private let pageZoomPreferences: BrowserDefaultPageZoomStore
    @ObservationIgnored private let chromeWebStoreProvider: BrowserChromeWebStoreProvider
    @ObservationIgnored private let mozillaAddonsProvider: BrowserMozillaAddonsProvider
    @ObservationIgnored private let dialogPresenter: BrowserDialogPresenter
    @ObservationIgnored private let popupTabHost: BrowserPopupTabHost
    @ObservationIgnored private let openNewTab: (URL) -> Void
    @ObservationIgnored var extensionSidebarDocuments: [BrowserExtensionSidebarKey: BrowserExtensionSidebarDocument] =
        [:]

    func openExtensionSidebarLink(_ url: URL) { openNewTab(url) }
    @ObservationIgnored private let openModifiedLink: ModifiedLinkOpener
    @ObservationIgnored private let backgroundPageDidUpdate: BackgroundPageUpdateHandler
    @ObservationIgnored private let openPeek: (BrowserPeekRequest) -> Void
    @ObservationIgnored private let splitLinkHost: BrowserSplitLinkHost
    @ObservationIgnored let linkDestinationHost: BrowserLinkDestinationHost
    @ObservationIgnored private let hostedNotificationCenter: (any BrowserHostedWebNotificationCentering)?
    @ObservationIgnored private let mediaSessionStore: BrowserMediaSessionStore?
    @ObservationIgnored private let activateHostedNotificationSource: (SpaceID, TabID) -> Void
    @ObservationIgnored private let loadHTTPAuthenticationCredential: HTTPAuthenticationCredentialLoader
    @ObservationIgnored private let saveHTTPAuthenticationCredential: HTTPAuthenticationCredentialSaver
    @ObservationIgnored private let websiteDataStoreRemover: any BrowserWebsiteDataStoreRemoving
    @ObservationIgnored private let contentRuleListProvider: any BrowserContentRuleListProviding
    @ObservationIgnored private var balancedContentRuleLists: [WKContentRuleList]?
    /// What each Space's protection level was at the last reconciliation, so the
    /// next one can tell a protection change the user made from a filter-list
    /// update that changed no policy at all. Nil until the first reconciliation.
    @ObservationIgnored private var reconciledContentBlockingPolicies: [SpaceID: BrowserContentBlockingPolicy]?
    @ObservationIgnored private var memoryPressureSource: (any DispatchSourceMemoryPressure)?
    @ObservationIgnored private var memoryPressureCoalescer = BrowserMemoryPressureCoalescer()
    @ObservationIgnored private var transientLeases: [UUID: WeakBrowserTransientPageLease] = [:]
    /// Pages announced to extensions that no tab in the session owns, resolved
    /// for the adapters WebKit asks about them.
    @ObservationIgnored private var transientExtensionPages: [TabID: BrowserPage] = [:]
    @ObservationIgnored private var extensionOffscreenDocuments:
        [ExtensionOffscreenDocumentKey: BrowserExtensionOffscreenDocument] = [:]
    @ObservationIgnored private var spacesReleasingData: Set<SpaceID> = []
    @ObservationIgnored private var spacesDeletingData: Set<SpaceID> = []
    /// Where unloaded tabs leave their WebKit session state. Always nil for a
    /// private pool, so private browsing cannot write one even if an archive is
    /// handed in.
    @ObservationIgnored private let tabStateArchive: (any BrowserTabStateArchiving)?
    @ObservationIgnored private var lastPrunedTabIDsByProfileID: [UUID: Set<TabID>] = [:]
    @ObservationIgnored private var backgroundPageSnapshots: [TabID: BrowserBackgroundPageSnapshot] = [:]
    @ObservationIgnored private var backgroundPageAssignments: [TabID: BrowserSpaceRuntimeAssignment] = [:]

    init(
        monitorsMemoryPressure: Bool = false,
        browsingMode: BrowserBrowsingMode = .standard,
        usesEphemeralWebsiteDataStores: Bool =
            BrowserLaunchIsolationPolicy.usesEphemeralProfileStorage(.current),
        pageZoomPreferences: BrowserDefaultPageZoomStore = .shared,
        extensionControllerPool: BrowserExtensionControllerPool = BrowserExtensionControllerPool(),
        chromeWebStoreProvider: BrowserChromeWebStoreProvider =
            BrowserChromeWebStoreProvider(),
        mozillaAddonsProvider: BrowserMozillaAddonsProvider =
            BrowserMozillaAddonsProvider(),
        permissionCenter: BrowserSitePermissionCenter = BrowserSitePermissionCenter(),
        hostedNotificationCenter:
            (any BrowserHostedWebNotificationCentering)? = nil,
        mediaSessionStore: BrowserMediaSessionStore? = nil,
        downloadLedger: BrowserDownloadLedger = BrowserDownloadLedger(),
        loadHTTPAuthenticationCredential:
            @escaping HTTPAuthenticationCredentialLoader = { _, _ in nil },
        saveHTTPAuthenticationCredential:
            @escaping HTTPAuthenticationCredentialSaver = { _, _ in },
        websiteDataStoreRemover:
            any BrowserWebsiteDataStoreRemoving = WebKitBrowserWebsiteDataStoreRemover(),
        contentRuleListProvider:
            any BrowserContentRuleListProviding = BrowserContentRuleListProvider.shared,
        tabStateArchive: (any BrowserTabStateArchiving)? = nil,
        popupTabHost: BrowserPopupTabHost = .unavailable,
        openNewTab: @escaping (URL) -> Void = { _ in },
        openModifiedLink: @escaping ModifiedLinkOpener = { _, _, _ in nil },
        backgroundPageDidUpdate: @escaping BackgroundPageUpdateHandler = { _ in nil },
        openPeek: @escaping (BrowserPeekRequest) -> Void = { _ in },
        splitLinkHost: BrowserSplitLinkHost = .unavailable,
        linkDestinationHost: BrowserLinkDestinationHost = .unavailable,
        activateHostedNotificationSource:
            @escaping (SpaceID, TabID) -> Void = { _, _ in },
        residencyDecisionProvider: @escaping ResidencyDecisionProvider = {
            page,
            isSelected in
            await page.residencyDecision(isSelected: isSelected)
        }
    ) {
        let dialogPresenter = BrowserDialogPresenter()
        self.residencyDecisionProvider = residencyDecisionProvider
        self.browsingMode = browsingMode
        self.usesEphemeralWebsiteDataStores =
            usesEphemeralWebsiteDataStores || browsingMode.isPrivate
        self.pageZoomPreferences = pageZoomPreferences
        self.tabStateArchive =
            self.usesEphemeralWebsiteDataStores
            ? nil
            : tabStateArchive
        self.extensionControllerPool = extensionControllerPool
        extensionWebpageMenuProvider = BrowserExtensionWebpageMenuProvider(
            extensionControllerPool: extensionControllerPool
        )
        self.chromeWebStoreProvider = chromeWebStoreProvider
        self.mozillaAddonsProvider = mozillaAddonsProvider
        self.permissionCenter = permissionCenter
        self.hostedNotificationCenter = hostedNotificationCenter
        self.mediaSessionStore = browsingMode.isPrivate ? nil : mediaSessionStore
        self.dialogPresenter = dialogPresenter
        self.popupTabHost = popupTabHost
        self.loadHTTPAuthenticationCredential = loadHTTPAuthenticationCredential
        self.saveHTTPAuthenticationCredential = saveHTTPAuthenticationCredential
        self.websiteDataStoreRemover = websiteDataStoreRemover
        self.contentRuleListProvider = contentRuleListProvider
        self.openNewTab = openNewTab
        self.openModifiedLink = openModifiedLink
        self.backgroundPageDidUpdate = backgroundPageDidUpdate
        self.openPeek = openPeek
        self.splitLinkHost = splitLinkHost
        self.linkDestinationHost = linkDestinationHost
        self.activateHostedNotificationSource = activateHostedNotificationSource
        downloadCenter = BrowserDownloadCenter(
            ledger: downloadLedger,
            promptForCredentials: { prompt, spaceName in
                await dialogPresenter.presentHTTPAuthentication(
                    prompt: prompt,
                    spaceName: spaceName
                )
            },
            allowsCredentialSaving: !browsingMode.isPrivate,
            loadCredential: loadHTTPAuthenticationCredential,
            saveCredential: saveHTTPAuthenticationCredential,
            approveRiskyDownload: { assessment, sourceURL, spaceName in
                await dialogPresenter.approveRiskyDownload(
                    assessment: assessment,
                    sourceURL: sourceURL,
                    spaceName: spaceName
                )
            },
            permissionCenter: permissionCenter,
            approveAutomaticDownload: { filename, origin, spaceName in
                await dialogPresenter.presentAutomaticDownloadPermission(
                    filename: filename,
                    origin: origin,
                    spaceName: spaceName
                )
            }
        )
        if monitorsMemoryPressure {
            installMemoryPressureSource()
        }
        pageZoomPreferences.register(self)
    }

    deinit {
        memoryPressureReleaseTask?.cancel()
        memoryPressureSource?.cancel()
    }

    var retainedTabIDs: Set<TabID> {
        _ = residencyRevision
        return Set(pages.keys)
    }

    func containsResidentPage(for tabID: TabID) -> Bool {
        _ = residencyRevision
        return pages[tabID] != nil
    }

    func containsResidentPage(
        matching assignment: BrowserTabRuntimeAssignment
    ) -> Bool {
        _ = residencyRevision
        guard let page = pages[assignment.tabID] else { return false }
        return page.spaceID == assignment.spaceID
            && page.profileID == assignment.profileID
    }

    func siteThemeIconAccent(for tabID: TabID) -> BrowserTabIconAccent? {
        pages[tabID]?.siteThemeIconAccent
    }

    func siteThemeIconAccent(
        matching assignment: BrowserTabRuntimeAssignment
    ) -> BrowserTabIconAccent? {
        guard let page = pages[assignment.tabID],
            page.spaceID == assignment.spaceID,
            page.profileID == assignment.profileID
        else { return nil }
        return page.siteThemeIconAccent
    }

    var retainedTransientPageCount: Int {
        pruneTransientLeases()
        return transientLeases.values.compactMap(\.value).filter { $0.page != nil }.count
    }

    var activePage: BrowserPage? {
        _ = residencyRevision
        guard let activeTabID else { return nil }
        return pages[activeTabID]
    }

    /// The resident page of a presented card, or `nil` for a tab that is not
    /// on screen right now.
    ///
    /// Membership is checked rather than residency alone: a background tab can
    /// keep a resident page for as long as memory allows, and handing one to a
    /// card would put a second host on a web view that already has one.
    func presentedPage(for tabID: TabID) -> BrowserPage? {
        _ = residencyRevision
        guard presentedTabIDs.contains(tabID) else { return nil }
        return pages[tabID]
    }

    func extensionWebView(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> WKWebView? {
        extensionPage(for: tabID, in: spaceID)?.webView
    }

    func startExtensionDownload(
        _ request: BrowserExtensionDownloadRequest,
        for tabID: TabID,
        in spaceID: SpaceID,
        isUserInitiated: Bool
    ) async throws -> Int {
        guard let page = extensionPage(for: tabID, in: spaceID) else {
            throw BrowserExtensionDownloadExecutionError.unavailable
        }
        return await downloadCenter.startExtensionDownload(
            request,
            in: page.webView,
            profileID: page.profileID,
            spaceID: page.spaceID,
            spaceName: page.spaceName,
            isUserInitiated: isUserInitiated
        )
    }

    func createExtensionOffscreenDocument(
        at url: URL,
        extensionBaseURL: URL,
        in spaceID: SpaceID
    ) async throws {
        let key = ExtensionOffscreenDocumentKey(
            spaceID: spaceID,
            extensionBaseURL: extensionBaseURL
        )
        guard extensionOffscreenDocuments[key] == nil else {
            throw BrowserExtensionOffscreenDocumentError.alreadyExists
        }
        guard
            let configuration =
                extensionControllerPool
                .extensionPageConfiguration(for: url, in: spaceID),
            configuration.baseURL == extensionBaseURL
        else {
            throw BrowserExtensionOffscreenDocumentError.unavailable
        }
        let document = BrowserExtensionOffscreenDocument(
            configuration: configuration.webViewConfiguration
        )
        extensionOffscreenDocuments[key] = document
        do {
            try await document.load(url)
        } catch {
            if extensionOffscreenDocuments[key] === document {
                extensionOffscreenDocuments[key] = nil
            }
            document.close()
            throw error
        }
    }

    func closeExtensionOffscreenDocument(
        extensionBaseURL: URL,
        in spaceID: SpaceID
    ) {
        let key = ExtensionOffscreenDocumentKey(
            spaceID: spaceID,
            extensionBaseURL: extensionBaseURL
        )
        extensionOffscreenDocuments.removeValue(forKey: key)?.close()
    }

    func hasExtensionOffscreenDocument(
        extensionBaseURL: URL,
        in spaceID: SpaceID
    ) -> Bool {
        extensionOffscreenDocuments[
            ExtensionOffscreenDocumentKey(
                spaceID: spaceID,
                extensionBaseURL: extensionBaseURL
            )
        ] != nil
    }

    func extensionOffscreenDocument(
        extensionBaseURL: URL,
        in spaceID: SpaceID
    ) -> BrowserExtensionHostedDocument? {
        guard
            let document = extensionOffscreenDocuments[
                ExtensionOffscreenDocumentKey(
                    spaceID: spaceID,
                    extensionBaseURL: extensionBaseURL
                )
            ],
            let url = document.url
        else {
            return nil
        }
        return BrowserExtensionHostedDocument(
            contextID: document.contextID,
            url: url,
            tabID: nil
        )
    }

    func loadExtensionURL(
        _ url: URL,
        for tabID: TabID,
        in spaceID: SpaceID,
        session: BrowserSession
    ) {
        // An unloaded background tab keeps the URL in the session and receives
        // the right configuration when it is next presented. Only a resident
        // tab has a live WebKit runtime to navigate now.
        guard let currentPage = pages[tabID],
            let space = session.space(id: spaceID),
            let tab = space.tabs.first(where: { $0.id == tabID })
        else { return }
        let replacesExtensionRuntime =
            currentPage.extensionBaseURL != nil
            && extensionControllerPool.extensionPageConfiguration(
                for: url,
                in: spaceID
            ) == nil
        let destinationPage = page(for: tab, space: space)
        if replacesExtensionRuntime {
            clearRuntimeNavigation(for: tabID)
        }
        destinationPage.load(url)
    }

    func extensionReaderModeState(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> BrowserReaderModeState {
        extensionPage(for: tabID, in: spaceID)?.readerModeState ?? .unavailable
    }

    func setExtensionReaderModeActive(
        _ isActive: Bool,
        for tabID: TabID,
        in spaceID: SpaceID
    ) async throws {
        guard let page = extensionPage(for: tabID, in: spaceID) else {
            throw BrowserReaderModeError.articleUnavailable
        }
        try await page.setReaderModeActive(isActive)
    }

    func extensionWindowGeometry(
        in spaceID: SpaceID
    ) -> BrowserExtensionWindowGeometry {
        guard let window = hostingWindow(for: spaceID) else {
            return .unavailable
        }
        let state: WKWebExtension.WindowState =
            if window.isMiniaturized {
                .minimized
            } else if window.styleMask.contains(.fullScreen) {
                .fullscreen
            } else if window.isZoomed {
                .maximized
            } else {
                .normal
            }
        return BrowserExtensionWindowGeometry(
            frame: window.frame,
            screenFrame: window.screen?.frame ?? NSScreen.main?.frame ?? .null,
            state: state
        )
    }

    /// The window presenting a Space. Spaces share one browser window, so this
    /// prefers the active page and otherwise accepts any resident page of the
    /// Space that is currently in a window.
    private func hostingWindow(for spaceID: SpaceID) -> NSWindow? {
        if let activePage, activePage.spaceID == spaceID,
            let window = activePage.webView.window
        {
            return window
        }
        return pages.values.first {
            $0.spaceID == spaceID && $0.webView.window != nil
        }?.webView.window
    }

    private func extensionPage(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> BrowserPage? {
        guard let page = pages[tabID] ?? transientExtensionPages[tabID],
            page.spaceID == spaceID
        else {
            return nil
        }
        return page
    }

    func prepareExtensionSelection(session: BrowserSession) {
        guard let tab = session.selectedTab,
            let space = session.selectedSpace,
            !spacesReleasingData.contains(space.id),
            !spacesDeletingData.contains(space.id)
        else {
            return
        }
        _ = page(for: tab, space: space)
        activate(tab.id, at: .now)
    }

    var canGoBack: Bool {
        guard let activeTabID else { return false }
        return activePage?.canGoBack == true
            || runtimeBackPagesByTabID[activeTabID] != nil
    }

    var canGoForward: Bool {
        guard let activeTabID else { return false }
        return activePage?.canGoForward == true
            || runtimeForwardPagesByTabID[activeTabID] != nil
    }

    var backHistory: [BrowserNavigationHistoryItem] {
        runtimeHistory(
            local: activePage?.backHistory ?? [],
            crossingTo: activeTabID.flatMap { runtimeBackPagesByTabID[$0] },
            continuation: \BrowserPage.backHistory
        )
    }

    var forwardHistory: [BrowserNavigationHistoryItem] {
        runtimeHistory(
            local: activePage?.forwardHistory ?? [],
            crossingTo: activeTabID.flatMap { runtimeForwardPagesByTabID[$0] },
            continuation: \BrowserPage.forwardHistory
        )
    }

    var hasActivePage: Bool {
        activePage?.url != nil
    }

    var isLoading: Bool {
        activePage?.isLoading == true
    }

    var pageZoomLabel: String {
        BrowserPageZoomPolicy.percentageLabel(for: activePage?.pageZoom ?? 1)
    }

    var readerModeState: BrowserReaderModeState {
        activePage?.readerModeState ?? .unavailable
    }

    var readerModeActionTitle: LocalizedStringResource {
        readerModeState.isActive ? "Hide Reader" : "Show Reader"
    }

    func select(
        tab: BrowserTab?,
        space: BrowserSpace?,
        at time: Date = .now
    ) {
        startInitialNavigations(
            presentCards(tab: tab, space: space, at: time)
        )
    }

    /// Builds and presents the cards `tab` brings on screen without navigating
    /// any of them, answering the cards whose first load is still owed.
    ///
    /// Creation and navigation are separate steps so a caller that has
    /// extensions attached can announce the new cards as tabs in between.
    /// WebKit resolves a content script's `runtime` messages by mapping its web
    /// view onto an announced tab, and a document-start script that runs before
    /// its card is announced is rejected rather than queued.
    private func presentCards(
        tab: BrowserTab?,
        space: BrowserSpace?,
        at time: Date
    ) -> [(tab: BrowserTab, page: BrowserPage)] {
        let interval = Self.lifecycleSignposter.beginInterval("Select Browser Page")
        defer {
            Self.lifecycleSignposter.endInterval("Select Browser Page", interval)
        }

        guard let tab, let space,
            !spacesReleasingData.contains(space.id),
            !spacesDeletingData.contains(space.id)
        else {
            deactivatePagePresentation(at: time)
            return []
        }
        // Every member of the selected tab's split group is a live card, so
        // each one is built and started here. A card the person can see must
        // never wait for focus to load: lazy loading is for tabs off screen.
        let members = presentedMembers(for: tab, in: space)
        let memberPages = members.map { (tab: $0, page: page(for: $0, space: space)) }
        activate(tab.id, presenting: members.map(\.id), at: time)
        return memberPages
    }

    private func startInitialNavigations(
        _ cards: [(tab: BrowserTab, page: BrowserPage)]
    ) {
        for card in cards {
            loadInitialURL(for: card.tab, into: card.page)
        }
    }

    private func openModifiedLink(
        _ url: URL,
        in spaceID: SpaceID,
        selecting: Bool
    ) {
        guard let registration = openModifiedLink(url, spaceID, selecting) else {
            return
        }
        guard !selecting else { return }
        let page = page(for: registration.tab, space: registration.space)
        observeBackgroundPage(
            page,
            for: registration.tab.id,
            in: registration.space
        )
        extensionControllerPool.reconcileExtensionState(in: registration.session)
        loadInitialURL(for: registration.tab, into: page)
        reconcileCredentialAccess(in: registration.session)
    }

    private func observeBackgroundPage(
        _ page: BrowserPage,
        for tabID: TabID,
        in space: BrowserSpace
    ) {
        backgroundPageAssignments[tabID] = BrowserSpaceRuntimeAssignment(space: space)
        backgroundPageSnapshots[tabID] = BrowserBackgroundPageSnapshot(page: page)
        trackBackgroundPageChanges(page, for: tabID)
    }

    private func trackBackgroundPageChanges(_ page: BrowserPage, for tabID: TabID) {
        withObservationTracking {
            _ = BrowserBackgroundPageSnapshot(page: page)
        } onChange: { [weak self, weak page] in
            Task { @MainActor in
                guard let self, let page else { return }
                self.backgroundPageDidChange(page, for: tabID)
            }
        }
    }

    private func backgroundPageDidChange(_ page: BrowserPage, for tabID: TabID) {
        guard pages[tabID] === page,
            let assignment = backgroundPageAssignments[tabID]
        else {
            forgetBackgroundPageObservation(for: tabID)
            return
        }
        let previous = backgroundPageSnapshots[tabID]
        let current = BrowserBackgroundPageSnapshot(page: page)
        backgroundPageSnapshots[tabID] = current
        trackBackgroundPageChanges(page, for: tabID)

        let initialNavigationSettled =
            current.completedNavigationCount > 0
            || current.hasNavigationFailure
            || (previous?.isLoading == true && !current.isLoading)
        if initialNavigationSettled,
            !presentedTabIDs.contains(tabID),
            inactiveSinceByTabID[tabID] == nil
        {
            inactiveSinceByTabID[tabID] = .now
        }

        guard previous != current, !presentedTabIDs.contains(tabID) else {
            return
        }
        let completedNavigationURL: URL? =
            if let previous,
                current.completedNavigationCount > previous.completedNavigationCount
            {
                page.url
            } else {
                nil
            }
        let update = BrowserBackgroundPageUpdate(
            tabID: tabID,
            assignment: assignment,
            url: current.url,
            title: current.title,
            faviconData: current.faviconData,
            iconAccent: current.iconAccent,
            estimatedProgress: current.estimatedProgress,
            isLoading: current.isLoading,
            readerModeState: current.readerModeState,
            completedNavigationURL: completedNavigationURL,
            processTerminationCount: current.processTerminationCount
        )
        guard let session = backgroundPageDidUpdate(update) else { return }
        extensionControllerPool.reconcileExtensionState(in: session)
        if completedNavigationURL != nil,
            let space = session.space(id: assignment.spaceID),
            space.profile.id == assignment.profileID
        {
            Task { @MainActor [weak self] in
                await self?.styleVisitedLinks(in: space)
            }
        }
    }

    private func forgetBackgroundPageObservation(for tabID: TabID) {
        backgroundPageSnapshots[tabID] = nil
        backgroundPageAssignments[tabID] = nil
    }

    /// The cards `tab` brings on screen, with the caller's own tab value in
    /// place of the Space's copy of it.
    ///
    /// Selection can hand over a tab the store has already moved on from — a
    /// restored saved location, say — and that fresher value is the one whose
    /// URL the initial load has to use. A tab the Space does not carry at all
    /// presents alone rather than not at all.
    private func presentedMembers(
        for tab: BrowserTab,
        in space: BrowserSpace
    ) -> [BrowserTab] {
        let members = space.presentedSplitMembers(for: tab.id)
        guard members.contains(where: { $0.id == tab.id }) else { return [tab] }
        return members.map { $0.id == tab.id ? tab : $0 }
    }

    func select(session: BrowserSession) {
        select(session: session, at: .now)
    }

    func select(session: BrowserSession, at time: Date) {
        let cards = presentCards(
            tab: session.selectedTab,
            space: session.selectedSpace,
            at: time
        )
        // Announce the cards before they navigate, so every new web view gets
        // the same standing with extensions that an ordinary tab open provides
        // by the time its content scripts run.
        extensionControllerPool.reconcileExtensionState(in: session)
        startInitialNavigations(cards)
        reconcileCredentialAccess(in: session)
    }

    /// Removes every rendered page from presentation without evicting their
    /// isolated WebKit runtimes. Re-selecting the tab restores the resident
    /// page, while protected content cannot remain visible behind a lock gate.
    ///
    /// All of it goes at once, not just the focused card: a Space locking with
    /// a split open has to take every card away, and half a split left on
    /// screen would be the privacy failure the gate exists to prevent.
    func deactivatePagePresentation(at time: Date = .now) {
        guard activeTabID != nil || !presentedTabIDs.isEmpty else { return }
        for tabID in presentedTabIDs {
            pages[tabID]?.focusRestoration.invalidate()
        }
        activePage?.focusRestoration.invalidate()
        for tabID in presentedTabIDs {
            inactiveSinceByTabID[tabID] = time
        }
        if let activeTabID, !presentedTabIDs.contains(activeTabID) {
            inactiveSinceByTabID[activeTabID] = time
        }
        presentedTabIDs = []
        activeTabID = nil
    }

    func restoreExtensions(in session: BrowserSession) async {
        guard !browsingMode.isPrivate else {
            BrowserExtensionStartupLog.skippedPrivateBrowsing()
            return
        }
        await extensionControllerPool.restoreEnabledExtensions(
            in: session.spaces
        )
        // Only now: an update pass replaces the very packages restoration has
        // just loaded, so arming the cadence any earlier would race it.
        extensionControllerPool.startExtensionUpdatesIfNeeded()
    }

    func prepareContentBlocking() async {
        guard balancedContentRuleLists == nil else { return }
        do {
            balancedContentRuleLists =
                try await contentRuleListProvider
                .balancedRuleLists()
            contentBlockingErrorDescription = nil
        } catch {
            contentBlockingErrorDescription = error.localizedDescription
        }
    }

    /// Brings every resident page in line with its Space's protection level.
    ///
    /// A rule-list change reaches a page as a swap on its `WKUserContentController`
    /// and nothing more: WebKit picks the new lists up on that page's next
    /// navigation, so a background filter-list refresh cannot reload a dozen tabs
    /// out from under someone who is typing in one of them. The single exception
    /// is a presented page — every card of a split, not only the focused one —
    /// and only when the user just changed the protection level of the Space it
    /// belongs to. That request came with an expectation of seeing the answer,
    /// and seeing it on one of three visible cards would read as a bug.
    func reconcileContentBlocking(in session: BrowserSession) async {
        if balancedContentRuleLists == nil,
            session.spaces.contains(where: {
                $0.browsingPreferences.contentBlockingPolicy == .balanced
            })
        {
            await prepareContentBlocking()
        }
        let policiesBySpaceID = Dictionary(
            uniqueKeysWithValues: session.spaces.map { space in
                (space.id, space.browsingPreferences.contentBlockingPolicy)
            }
        )
        let userChangedSpaceIDs = spaceIDsWithUserChangedPolicy(policiesBySpaceID)
        reconciledContentBlockingPolicies = policiesBySpaceID
        for (tabID, page) in pages {
            let isPresentedPage = presentedTabIDs.contains(tabID)
            page.applyContentBlocking(
                policy: policiesBySpaceID[page.spaceID] ?? .off,
                balancedRuleLists: balancedContentRuleLists ?? [],
                activation: isPresentedPage
                    && userChangedSpaceIDs.contains(page.spaceID)
                    ? .immediately
                    : .onNextNavigation
            )
        }
        for page in suspendedPagesByTabID.values.flatMap({ $0 }) {
            page.applyContentBlocking(
                policy: policiesBySpaceID[page.spaceID] ?? .off,
                balancedRuleLists: balancedContentRuleLists ?? [],
                activation: .onNextNavigation
            )
        }
        pruneTransientLeases()
        // A Peek is never a presented card, so its rules change under the same
        // next-navigation rule every background page follows.
        for lease in transientLeases.values.compactMap(\.value) {
            lease.applyContentBlocking(
                policy: policiesBySpaceID[lease.spaceID] ?? .off,
                balancedRuleLists: balancedContentRuleLists ?? []
            )
        }
    }

    /// The Spaces whose protection level changed since the last reconciliation.
    ///
    /// The first reconciliation adopts what it finds instead of calling every
    /// Space changed, so opening a window — where pages can be built before the
    /// rule lists finish compiling — never reloads the page it just opened.
    private func spaceIDsWithUserChangedPolicy(
        _ policiesBySpaceID: [SpaceID: BrowserContentBlockingPolicy]
    ) -> Set<SpaceID> {
        guard let reconciledContentBlockingPolicies else { return [] }
        return Set(
            policiesBySpaceID.compactMap { spaceID, policy in
                guard let previous = reconciledContentBlockingPolicies[spaceID],
                    previous != policy
                else { return nil }
                return spaceID
            }
        )
    }

    /// Recompiles from the provider and swaps the result into every resident page.
    /// Reached from a filter-list update, which is not something the user asked
    /// for right now, so no page is reloaded for it.
    func reloadContentBlocking(in session: BrowserSession) async {
        balancedContentRuleLists = nil
        await reconcileContentBlocking(in: session)
    }

    func reconcile(validTabIDs: Set<TabID>) {
        let removedTabIDs = Set(pages.keys).subtracting(validTabIDs)
        for tabID in removedTabIDs {
            // These tabs are gone from the tab list rather than unloaded after
            // idling, so their state is not worth writing out here. Whether it
            // is worth keeping is settled by the session sweep, which can tell an
            // archived tab from a deleted one.
            evictPage(tabID, preservingTabState: false)
        }
        if let activeTabID, !validTabIDs.contains(activeTabID) {
            self.activeTabID = nil
        }
        pruneCards(keeping: validTabIDs)
    }

    /// Drops cards for tabs that no longer exist. A split whose member was
    /// closed keeps presenting the rest; presentation is derived per selection,
    /// so a run that is no longer renderable collapses on the next one.
    private func pruneCards(keeping validTabIDs: Set<TabID>) {
        guard presentedTabIDs.contains(where: { !validTabIDs.contains($0) })
        else { return }
        presentedTabIDs = presentedTabIDs.filter { validTabIDs.contains($0) }
    }

    func reconcile(session: BrowserSession) {
        let tabsByID = Dictionary(
            uniqueKeysWithValues: session.spaces.flatMap { space in
                space.tabs.map { tab in
                    (tab.id, (tab: tab, space: space))
                }
            }
        )
        let assignments = Dictionary(
            uniqueKeysWithValues: session.tabRuntimeAssignments.map {
                ($0.tabID, $0)
            }
        )
        let invalidTabIDs: Set<TabID> = Set(
            pages.compactMap { tabID, page in
                guard let assignment = assignments[tabID],
                    assignment.spaceID == page.spaceID,
                    assignment.profileID == page.profileID
                else {
                    return tabID
                }
                return nil
            })
        let archivedAssignments = Dictionary(
            uniqueKeysWithValues: session.spaces.flatMap { space in
                space.archivedTabs.map { archivedTab in
                    (archivedTab.id, BrowserSpaceRuntimeAssignment(space: space))
                }
            }
        )
        for tabID in invalidTabIDs {
            guard let page = pages[tabID],
                let assignment = archivedAssignments[tabID],
                assignment.spaceID == page.spaceID,
                assignment.profileID == page.profileID
            else { continue }
            // Closing removes the tab from the live runtime assignments before
            // reconciliation. Capture its WebKit stack while the page still
            // exists; releasing first leaves both restore paths with only the
            // tab's final URL.
            archiveTabState(for: tabID)
        }
        releasePages(for: invalidTabIDs)
        for (tabID, page) in pages {
            guard let resident = tabsByID[tabID],
                resident.space.id == page.spaceID,
                resident.space.profile.id == page.profileID
            else { continue }
            page.updateNavigationContext(
                tab: resident.tab,
                automaticallyOpensPeek: BrowserLinkPreferenceStore.shared
                    .preferences.automaticallyOpensPeek
            )
        }
        pruneArchivedTabStates(in: session)
        extensionControllerPool.reconcileExtensionState(in: session)
        reconcileCredentialAccess(in: session)
    }

    func reconcileCredentialAccess(in session: BrowserSession) {
        let enabledBySpaceID = Dictionary(
            uniqueKeysWithValues: session.spaces.map {
                ($0.id, $0.credentialPreferences.isEnabled)
            }
        )
        for (spaceID, isEnabled) in enabledBySpaceID {
            downloadCenter.setCredentialAccessEnabled(isEnabled, in: spaceID)
        }
        for page in pages.values {
            page.setCredentialAccessEnabled(
                enabledBySpaceID[page.spaceID] ?? false
            )
        }
        for page in suspendedPagesByTabID.values.flatMap({ $0 }) {
            page.setCredentialAccessEnabled(
                enabledBySpaceID[page.spaceID] ?? false
            )
        }
        pruneTransientLeases()
        for lease in transientLeases.values.compactMap(\.value) {
            lease.setCredentialAccessEnabled(
                enabledBySpaceID[lease.spaceID] ?? false
            )
        }
    }

    /// Drops archived state for tabs a Space no longer has at all.
    ///
    /// Archived tabs keep theirs: reopening a closed tab is a restore path, and it
    /// is the one place the state is most worth having. Only a tab that is neither
    /// current nor archived — permanently deleted, or aged out of the archive — has
    /// nothing left to restore into.
    private func pruneArchivedTabStates(in session: BrowserSession) {
        guard let tabStateArchive else { return }
        var tabIDsByProfileID: [UUID: Set<TabID>] = [:]
        for space in session.spaces {
            let tabIDs = Set(space.tabs.map(\.id) + space.archivedTabs.map(\.tab.id))
            tabIDsByProfileID[space.profile.id, default: []].formUnion(tabIDs)
        }
        // Reconciliation runs on every session change, and a sweep reads a
        // directory per profile. Only the tab membership can change what the sweep
        // would do, so an unchanged membership skips it.
        guard !tabIDsByProfileID.isEmpty,
            tabIDsByProfileID != lastPrunedTabIDsByProfileID
        else { return }
        lastPrunedTabIDsByProfileID = tabIDsByProfileID
        tabStateArchive.pruneStates(keeping: tabIDsByProfileID)
    }

    /// Writes out the WebKit session state of every resident page. The app calls
    /// this when a scene stops being active, so state survives a quit before an
    /// inactive page reaches its idle deadline.
    func archiveResidentTabStates() {
        guard tabStateArchive != nil else { return }
        for tabID in pages.keys {
            archiveTabState(for: tabID)
        }
    }

    func flushPendingTabStateWrites() async {
        await tabStateArchive?.flushPendingWrites()
    }

    /// Reading `interactionState` is main-actor work; the archive takes the write
    /// off the main thread from here.
    private func archiveTabState(for tabID: TabID) {
        guard let tabStateArchive, let page = pages[tabID] else { return }
        // An adopted popup's window is WebKit's to drive, and its tab is a
        // web-content artefact rather than something the user placed, so it is
        // never archived.
        guard !page.wasOpenedAsPopup, let state = page.interactionState else { return }
        tabStateArchive.archive(
            interactionState: state,
            url: page.url,
            profileID: page.profileID,
            tabID: tabID
        )
    }

    /// The state archived for `tab`, once it is one this build may restore and one
    /// that still belongs where the tab points.
    private func archivedInteractionState(
        for tab: BrowserTab,
        profileID: UUID,
        expecting url: URL
    ) -> Data? {
        guard let tabStateArchive,
            let archived = tabStateArchive.archivedState(
                profileID: profileID,
                tabID: tab.id
            ),
            let envelope = BrowserTabStateEnvelope.decode(archived),
            envelope.isRestorable,
            BrowserTabStateRestorePolicy.restoresArchivedState(
                archivedURL: envelope.url,
                tabURL: url
            )
        else { return nil }
        return envelope.interactionState
    }

    func reconcileTabIcons(in session: BrowserSession) {
        let tabsByID = Dictionary(
            uniqueKeysWithValues: session.spaces.flatMap { space in
                space.tabs.map { ($0.id, $0) }
            }
        )
        for (tabID, page) in pages {
            guard let tab = tabsByID[tabID] else { continue }
            page.updateNavigationContext(
                tab: tab,
                automaticallyOpensPeek: BrowserLinkPreferenceStore.shared
                    .preferences.automaticallyOpensPeek
            )
        }
    }

    func deleteData(for space: BrowserSpace) async throws {
        guard spacesDeletingData.insert(space.id).inserted else { return }
        defer { spacesDeletingData.remove(space.id) }

        await releaseWindowRuntime(for: space)
        if !browsingMode.isPrivate {
            let extensionControllerProbe =
                try await extensionControllerPool
                .deleteData(for: space)
            await BrowserSpaceDataReleaseBarrier.waitForRetainedViews(
                [extensionControllerProbe]
            )
        }
        await BrowserFaviconFallbackLoader.shared.removeAll(
            for: space.profile.id
        )
        // Deleting a Space deletes its WebKit data, so the archived session state
        // of its tabs goes with it: nothing may outlive the profile it describes.
        tabStateArchive?.removeStates(profileID: space.profile.id)
        serverTrustOverrides.removeApprovals(for: space.profile.id)
        if !usesEphemeralWebsiteDataStores {
            try await websiteDataStoreRemover.removePersistentDataStore(
                for: space.profile
            )
        }
        permissionCenter.reset(spaceID: space.id)
    }

    func releaseWindowRuntime(for space: BrowserSpace) async {
        guard spacesReleasingData.insert(space.id).inserted else { return }
        defer { spacesReleasingData.remove(space.id) }

        let tabIDs = Set(
            space.tabs.map(\.id) + space.archivedTabs.map(\.id)
        )
        releaseExtensionOffscreenDocuments(in: space.id)
        let pageReleaseProbes =
            releasePages(for: tabIDs)
            + releaseTransientPages(in: space.id)
        await BrowserSpaceDataReleaseBarrier.waitForRetainedViews(
            pageReleaseProbes
        )
        downloadCenter.deleteRecords(
            profileID: space.profile.id,
            spaceID: space.id
        )
        if usesEphemeralWebsiteDataStores {
            ephemeralDataStores.removeValue(forKey: space.profile.id)
        }
    }

    func closePrivateBrowsingSession(_ session: BrowserSession) {
        guard browsingMode.isPrivate else { return }
        releasePages(for: Set(pages.keys))
        releaseAllTransientPages()
        releaseAllExtensionOffscreenDocuments()
        for space in session.spaces {
            downloadCenter.deleteRecords(
                profileID: space.profile.id,
                spaceID: space.id
            )
            permissionCenter.reset(spaceID: space.id)
            Task {
                await BrowserFaviconFallbackLoader.shared.removeAll(
                    for: space.profile.id
                )
            }
        }
        ephemeralDataStores.removeAll()
    }

    func load(_ url: URL) {
        activePage?.load(url)
    }

    /// The cards a visited-link restyle applies to.
    ///
    /// Every presented member, not only the focused one: a link followed in one
    /// card is followed for the window, and leaving its neighbour showing the same
    /// link unstyled until that neighbour navigates for its own reasons is a lie
    /// about what has been read. The focused tab is included even in the frame
    /// where popup adoption has activated a tab the presented list has not caught
    /// up with, and pages belonging to another Space or profile are excluded — the
    /// history being applied is this Space's.
    func visitedLinkStylingTabIDs(in space: BrowserSpace) -> [TabID] {
        _ = residencyRevision
        var seen: Set<TabID> = []
        return (presentedTabIDs + [activeTabID].compactMap { $0 }).filter { tabID in
            guard seen.insert(tabID).inserted, let page = pages[tabID] else {
                return false
            }
            return page.spaceID == space.id && page.profileID == space.profile.id
        }
    }

    func styleVisitedLinks(in space: BrowserSpace) async {
        for tabID in visitedLinkStylingTabIDs(in: space) {
            await pages[tabID]?.styleVisitedLinks(history: space.history)
        }
    }

    func makeTransientPageLease(
        url: URL,
        in space: BrowserSpace,
        onUserActivity: @escaping () -> Void = {},
        onDownloadOnlyNavigation: (() -> Void)? = nil
    ) -> BrowserTransientPageLease? {
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard canHostTransientPage(matching: assignment) else { return nil }
        let tabID = TabID()
        let makeTransientPage = { [weak self] () -> BrowserPage? in
            guard let self,
                canHostTransientPage(matching: assignment)
            else { return nil }
            return makePage(
                space: space,
                extensionConfiguration:
                    extensionControllerPool.extensionPageConfiguration(
                        for: url,
                        in: space.id
                    )
            )
        }
        guard let initialPage = makeTransientPage() else { return nil }
        // Announce the page before the lease's initializer navigates it. WebKit
        // injects content scripts during that load and answers their `runtime`
        // messages only for a web view it can map onto an announced tab, so a
        // page announced afterwards leaves its first script unanswered for the
        // life of the document — the state a reload is otherwise needed to clear.
        announceTransientExtensionPage(
            initialPage,
            as: tabID,
            url: url,
            in: space.id
        )
        guard let page = transientExtensionPages[tabID] else { return nil }
        let lease = BrowserTransientPageLease(
            extensionTabID: tabID,
            page: page,
            url: url,
            contentBlockingPolicy:
                space.browsingPreferences.contentBlockingPolicy,
            balancedContentRuleLists: balancedContentRuleLists ?? [],
            rebuild: makeTransientPage,
            userActivity: onUserActivity,
            onDownloadOnlyNavigation: onDownloadOnlyNavigation,
            extensionPageDidChange: { [weak self] page in
                guard let self else { return }
                if let page {
                    announceTransientExtensionPage(
                        page,
                        as: tabID,
                        url: url,
                        in: space.id
                    )
                } else {
                    withdrawTransientExtensionPage(tabID, in: space.id)
                }
            }
        )
        transientLeases[lease.id] = WeakBrowserTransientPageLease(lease)
        return lease
    }

    /// Makes `page` resolvable under `tabID` and tells extensions it exists.
    ///
    /// Resolution is established first: WebKit asks the adapter for its web view
    /// while handling the announcement, and an adapter that cannot answer is a
    /// tab extensions can see but not reach.
    private func announceTransientExtensionPage(
        _ page: BrowserPage,
        as tabID: TabID,
        url: URL,
        in spaceID: SpaceID
    ) {
        transientExtensionPages[tabID] = page
        extensionControllerPool.registerTransientExtensionTab(
            BrowserExtensionTransientTab(id: tabID, url: url),
            in: spaceID
        )
    }

    private func withdrawTransientExtensionPage(
        _ tabID: TabID,
        in spaceID: SpaceID
    ) {
        guard transientExtensionPages.removeValue(forKey: tabID) != nil else {
            return
        }
        extensionControllerPool.unregisterTransientExtensionTab(
            tabID,
            in: spaceID
        )
    }

    @discardableResult
    func adoptTransientPage(
        _ lease: BrowserTransientPageLease,
        as tabID: TabID,
        in space: BrowserSpace
    ) -> Bool {
        guard !spacesReleasingData.contains(space.id),
            !spacesDeletingData.contains(space.id),
            let page = lease.page
        else { return false }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard lease.assignment == assignment,
            page.spaceID == assignment.spaceID,
            page.profileID == assignment.profileID
        else { return false }
        guard lease.relinquishPage() === page else { return false }
        transientLeases.removeValue(forKey: lease.id)
        pages[tabID] = page
        residencyRevision &+= 1
        activate(tabID, at: .now)
        if let tab = space.tabs.first(where: { $0.id == tabID }) {
            page.updateNavigationContext(
                tab: tab,
                automaticallyOpensPeek: BrowserLinkPreferenceStore.shared
                    .preferences.automaticallyOpensPeek
            )
        }
        return true
    }

    private func canHostTransientPage(
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        !spacesReleasingData.contains(assignment.spaceID)
            && !spacesDeletingData.contains(assignment.spaceID)
    }

    func navigatePopupInCurrentPage(
        _ request: URLRequest,
        opener: BrowserPage
    ) -> Bool {
        guard request.url != nil,
            !spacesReleasingData.contains(opener.spaceID),
            !spacesDeletingData.contains(opener.spaceID),
            transientLeases.values.contains(where: {
                $0.value?.page === opener
            })
        else { return false }
        opener.loadWebContentRequest(request)
        return true
    }

    /// Adopts the web view WebKit pre-made for a popup as a new selected tab in
    /// the opener's Space.
    ///
    /// Declines — leaving the coordinator to route the destination into an
    /// ordinary tab — when the opener is not a resident page of this pool.
    /// Transient openers have already had the opportunity to keep the request in
    /// their lease before this adoption path is reached.
    ///
    /// Per-Space isolation needs no work here: WebKit derives the popup's
    /// configuration from the opener's, so it already carries the opener's
    /// `websiteDataStore` and web extension controller. The Space lookup only
    /// confirms the tab landed in the opener's own profile.
    func adoptPopupWebView(
        configuration: WKWebViewConfiguration,
        requestedURL: URL?,
        opener: BrowserPage
    ) -> WKWebView? {
        guard tabID(for: opener) != nil,
            !spacesReleasingData.contains(opener.spaceID),
            !spacesDeletingData.contains(opener.spaceID),
            let registration = popupTabHost.openTab(requestedURL, opener.spaceID),
            registration.space.id == opener.spaceID,
            registration.space.profile.id == opener.profileID
        else { return nil }

        let page = makePage(
            space: registration.space,
            tabID: registration.tab.id,
            adoptedConfiguration: configuration
        )
        page.markOpenedAsPopup()
        page.updateNavigationContext(
            tab: registration.tab,
            automaticallyOpensPeek: BrowserLinkPreferenceStore.shared
                .preferences.automaticallyOpensPeek
        )
        pages[registration.tab.id] = page
        residencyRevision &+= 1
        activate(registration.tab.id, at: .now)
        return page.webView
    }

    /// Honors `window.close()` by closing the popup's tab through the same store
    /// path the tab list's close control uses. The page itself is released after
    /// the WebKit callback unwinds, because tearing a web view down inside its
    /// own delegate callback is not safe.
    func closeWebContentInitiatedPage(_ page: BrowserPage) {
        guard page.wasOpenedAsPopup, let tabID = tabID(for: page) else { return }
        popupTabHost.closeTab(tabID, page.spaceID)
        Task { @MainActor [weak self] in
            self?.unloadPage(for: tabID)
        }
    }

    func discardDownloadOnlyPage(_ page: BrowserPage) {
        if let entry = transientLeases.first(where: { $0.value.value?.page === page }),
            let lease = entry.value.value,
            lease.discardForDownloadOnlyNavigation()
        {
            transientLeases.removeValue(forKey: entry.key)
            return
        }
        if let tabID = tabID(for: page), pages[tabID] === page,
            !presentedTabIDs.contains(tabID),
            inactiveSinceByTabID[tabID] == nil
        {
            inactiveSinceByTabID[tabID] = .now
        }
        closeWebContentInitiatedPage(page)
    }

    func activateNotificationSourcePage(_ page: BrowserPage) {
        guard let tabID = tabID(for: page) else { return }
        activateHostedNotificationSource(page.spaceID, tabID)
    }

    func routeHostedWebNotificationMessage(_ message: WKScriptMessage) {
        guard let sourceWebView = message.webView,
            let page = pages.values.first(where: { $0.webView === sourceWebView })
                ?? suspendedPagesByTabID.values
                .joined()
                .first(where: { $0.webView === sourceWebView })
        else { return }
        page.receiveHostedWebNotificationMessage(message)
    }

    func routeGeolocationMessage(_ message: WKScriptMessage) {
        guard let sourceWebView = message.webView,
            let page = pages.values.first(where: { $0.webView === sourceWebView })
                ?? suspendedPagesByTabID.values
                .joined()
                .first(where: { $0.webView === sourceWebView })
        else { return }
        page.receiveGeolocationMessage(message)
    }

    func routeBlockedPopupMessage(_ message: WKScriptMessage) {
        guard let sourceWebView = message.webView,
            let page = pages.values.first(where: { $0.webView === sourceWebView })
                ?? suspendedPagesByTabID.values
                .joined()
                .first(where: { $0.webView === sourceWebView })
        else { return }
        page.receiveBlockedPopupMessage(message)
    }

    func routeMediaSessionMessage(_ message: WKScriptMessage) {
        guard let sourceWebView = message.webView,
            let page = pages.values.first(where: { $0.webView === sourceWebView })
                ?? suspendedPagesByTabID.values
                .joined()
                .first(where: { $0.webView === sourceWebView })
        else { return }
        page.receiveMediaSessionMessage(message)
    }

    func replaceExtensionPageNavigation(
        _ page: BrowserPage,
        with destinationURL: URL
    ) {
        guard let tabID = tabID(for: page),
            pages[tabID] === page,
            page.extensionBaseURL != nil
        else { return }
        _ = extensionControllerPool.replaceExtensionPageNavigation(
            destinationURL,
            tabID: tabID,
            spaceID: page.spaceID
        )
    }

    func goBack() {
        guard let activeTabID, let page = activePage else { return }
        if page.canGoBack {
            page.goBack()
            return
        }
        crossRuntimeHistoryBackward(for: activeTabID)
    }

    func goForward() {
        guard let activeTabID, let page = activePage else { return }
        if page.canGoForward {
            page.goForward()
            return
        }
        crossRuntimeHistoryForward(for: activeTabID)
    }

    func goBack(to item: BrowserNavigationHistoryItem) {
        guard let activeTabID, let page = activePage else { return }
        let localCount = page.backHistory.count
        guard item.depth > localCount else {
            page.goBack(toDepth: item.depth)
            return
        }
        guard
            let destinationPage = crossRuntimeHistoryBackward(
                for: activeTabID
            )
        else { return }
        let destinationDepth = item.depth - localCount - 1
        if destinationDepth > 0 {
            destinationPage.goBack(toDepth: destinationDepth)
        }
    }

    func goForward(to item: BrowserNavigationHistoryItem) {
        guard let activeTabID, let page = activePage else { return }
        let localCount = page.forwardHistory.count
        guard item.depth > localCount else {
            page.goForward(toDepth: item.depth)
            return
        }
        guard
            let destinationPage = crossRuntimeHistoryForward(
                for: activeTabID
            )
        else { return }
        let destinationDepth = item.depth - localCount - 1
        if destinationDepth > 0 {
            destinationPage.goForward(toDepth: destinationDepth)
        }
    }

    func unloadPage(for tabID: TabID) {
        // Archived before the page is torn down: a tab closed by hand can be
        // reopened, and a tab unloaded by hand is expected to come back where it
        // was left.
        archiveTabState(for: tabID)
        guard let page = pages.removeValue(forKey: tabID) else { return }
        forgetBackgroundPageObservation(for: tabID)
        page.prepareForSpaceDeletion()
        releaseSuspendedPages(for: tabID)
        inactiveSinceByTabID[tabID] = nil
        if activeTabID == tabID { activeTabID = nil }
        presentedTabIDs.removeAll { $0 == tabID }
        residencyRevision &+= 1
    }

    @discardableResult
    func unloadPage(
        for tabID: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let page = pages[tabID],
            page.spaceID == assignment.spaceID,
            page.profileID == assignment.profileID
        else { return false }
        unloadPage(for: tabID)
        return true
    }

    /// Releases a Space's resident pages without archiving them. Normal Space
    /// switching and locking preserve residency and do not call this teardown.
    func unloadPages(in spaceID: SpaceID) {
        let tabIDs = Set(
            pages.compactMap { tabID, page in
                page.spaceID == spaceID ? tabID : nil
            }
        )
        _ = releasePages(for: tabIDs)
        _ = releaseTransientPages(in: spaceID)
    }

    /// Hides a protected Space without unloading its tabs. Unlocking can reuse
    /// the same WebKit pages, including scroll position and unsaved form state.
    /// Resident pages remain subject to normal idle and memory-pressure limits.
    ///
    /// Previously archived state is still purged from disk. This preserves only
    /// live pages, not a disk snapshot of a protected Space. The access views
    /// gate ordinary and transient content until authentication succeeds.
    func relockProtectedSpace(_ space: BrowserSpace) {
        guard space.accessPolicy.requiresAuthentication else { return }
        closeExtensionSidebars(inSpace: space.id)
        // A background Space can still remember its editor after departure.
        // Locking ends that focus session even though its pages stay resident.
        let retainedPages =
            Array(pages.values)
            + suspendedPagesByTabID.values.flatMap { $0 }
            + Array(runtimeBackPagesByTabID.values)
            + Array(runtimeForwardPagesByTabID.values)
            + Array(transientExtensionPages.values)
            + transientLeases.values.compactMap { $0.value?.page }
        for page in retainedPages where page.spaceID == space.id {
            page.focusRestoration.invalidate()
        }
        if activePage?.spaceID == space.id
            || presentedTabIDs.contains(where: { pages[$0]?.spaceID == space.id })
        {
            deactivatePagePresentation()
        }
        tabStateArchive?.removeStates(profileID: space.profile.id)
    }

    func reloadOrStop(in session: BrowserSession) {
        reload(.standard, selectedBy: session)
    }

    func forceReload(in session: BrowserSession) {
        guard let tab = session.selectedTab,
            let space = session.selectedSpace
        else { return }
        let residentPage = pages[tab.id]
        let canReloadResidentPage =
            residentPage?.spaceID == space.id
            && residentPage?.profileID == space.profile.id
            && residentPage?.url != nil
        select(session: session)
        guard canReloadResidentPage else { return }
        activePage?.reload()
    }

    func stopLoading() {
        activePage?.stopLoading()
    }

    func reloadFromOrigin(in session: BrowserSession) {
        reload(.fromOrigin, selectedBy: session)
    }

    func clearSiteDataAndReload() async {
        await activePage?.clearSiteDataAndReload()
    }

    func presentFind() {
        activePage?.presentFind()
    }

    func showWebInspector() {
        activePage?.showWebInspector()
    }

    func toggleReaderMode() {
        activePage?.toggleReaderMode()
    }

    @discardableResult
    func zoomIn() -> Bool {
        activePage?.zoomIn() == true
    }

    @discardableResult
    func zoomOut() -> Bool {
        activePage?.zoomOut() == true
    }

    @discardableResult
    func resetZoom() -> Bool {
        activePage?.resetZoom() == true
    }

    func defaultPageZoomDidChange(to zoom: CGFloat) {
        var visited: Set<ObjectIdentifier> = []
        let retainedPages =
            Array(pages.values)
            + suspendedPagesByTabID.values.flatMap { $0 }
            + Array(runtimeBackPagesByTabID.values)
            + Array(runtimeForwardPagesByTabID.values)
            + Array(transientExtensionPages.values)
            + transientLeases.values.compactMap { $0.value?.page }
        for page in retainedPages
        where visited.insert(ObjectIdentifier(page)).inserted {
            page.applyDefaultPageZoom(zoom)
        }
    }

    @discardableResult
    func copyPageLink() -> Bool {
        activePage?.copyPageLink() == true
    }

    @discardableResult
    func copyPageLinkAsMarkdown() -> Bool {
        activePage?.copyPageLinkAsMarkdown() == true
    }

    func pullFavicon(
        for tabID: TabID
    ) async -> (data: Data, iconAccent: BrowserTabIconAccent?)? {
        guard let page = pages[tabID], let data = await page.pullFavicon() else {
            return nil
        }
        return (data, page.siteThemeIconAccent)
    }

    func pullFavicon(
        for tabID: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) async -> (data: Data, iconAccent: BrowserTabIconAccent?)? {
        guard let page = pages[tabID],
            page.spaceID == assignment.spaceID,
            page.profileID == assignment.profileID,
            let data = await page.pullFavicon(),
            pages[tabID] === page
        else { return nil }
        return (data, page.siteThemeIconAccent)
    }

    func sharePage() {
        activePage?.sharePage()
    }

    func printPage() {
        activePage?.printPage()
    }

    func exportPDF() {
        activePage?.exportPDF()
    }

    func exportWebArchive() {
        activePage?.exportWebArchive()
    }

    /// WebKit pages stay resident until explicit unloading or real system
    /// pressure. A pressure pass is deliberately asynchronous because WebKit is
    /// the source of truth for media playback and capture activity.
    func handleMemoryPressure(
        _ level: BrowserMemoryPressureLevel,
        at time: Date = .now
    ) {
        guard memoryPressureCoalescer.shouldHandle(level, at: time) else { return }
        releaseTransientPages(for: level)
        memoryPressureReleaseTask?.cancel()
        memoryPressureReleaseTask = Task { @MainActor [weak self] in
            await self?.releaseInactivePages(for: level)
        }
    }

    func waitForPendingMemoryPressureResponse() async {
        await memoryPressureReleaseTask?.value
    }

    /// Handles one kernel pressure event. The raw event has to be captured inside
    /// the dispatch source's own handler, so it arrives here as a value rather than
    /// being read back off the source.
    func handleMemoryPressureEvent(
        _ event: DispatchSource.MemoryPressureEvent,
        at time: Date = .now
    ) {
        handleMemoryPressure(
            event.contains(.critical) ? .critical : .warning,
            at: time
        )
    }

    private func page(for tab: BrowserTab, space: BrowserSpace) -> BrowserPage {
        let extensionConfiguration = tab.url.flatMap {
            extensionControllerPool.extensionPageConfiguration(
                for: $0,
                in: space.id
            )
        }
        if let existingPage = pages[tab.id] {
            if existingPage.spaceID == space.id,
                existingPage.profileID == space.profile.id
            {
                let page = page(
                    matching: extensionConfiguration,
                    for: tab.id,
                    replacing: existingPage,
                    in: space
                )
                page.setCredentialAccessEnabled(
                    space.credentialPreferences.isEnabled
                )
                page.updateNavigationContext(
                    tab: tab,
                    automaticallyOpensPeek: BrowserLinkPreferenceStore.shared
                        .preferences.automaticallyOpensPeek
                )
                return page
            }
            // The tab moved to another Space, so the state archived under its old
            // profile describes a runtime it no longer belongs to.
            tabStateArchive?.removeState(
                profileID: existingPage.profileID,
                tabID: tab.id
            )
            existingPage.prepareForSpaceDeletion()
            pages.removeValue(forKey: tab.id)
            forgetBackgroundPageObservation(for: tab.id)
            releaseSuspendedPages(for: tab.id)
            inactiveSinceByTabID[tab.id] = nil
        }
        let page = makePage(
            space: space,
            tabID: tab.id,
            extensionConfiguration: extensionConfiguration
        )
        page.updateNavigationContext(
            tab: tab,
            automaticallyOpensPeek: BrowserLinkPreferenceStore.shared
                .preferences.automaticallyOpensPeek
        )
        pages[tab.id] = page
        residencyRevision &+= 1
        return page
    }

    private func page(
        matching extensionConfiguration: BrowserExtensionPageConfiguration?,
        for tabID: TabID,
        replacing currentPage: BrowserPage,
        in space: BrowserSpace
    ) -> BrowserPage {
        guard !currentPage.matches(extensionConfiguration) else {
            return currentPage
        }

        var suspendedPages = suspendedPagesByTabID[tabID] ?? []
        let replacement: BrowserPage
        if let index = suspendedPages.firstIndex(where: {
            $0.matches(extensionConfiguration)
        }) {
            replacement = suspendedPages.remove(at: index)
        } else {
            replacement = makePage(
                space: space,
                tabID: tabID,
                extensionConfiguration: extensionConfiguration
            )
        }
        if currentPage.extensionBaseURL == nil,
            replacement.extensionBaseURL != nil
        {
            runtimeBackPagesByTabID[tabID] = currentPage
            runtimeForwardPagesByTabID[tabID] = nil
        }
        suspendedPages.append(currentPage)
        suspendedPagesByTabID[tabID] = suspendedPages
        pages[tabID] = replacement
        residencyRevision &+= 1
        return replacement
    }

    /// Builds a page for `space`. Popup and extension-page configurations are
    /// both supplied by WebKit and must be used exactly as handed over.
    private func makePage(
        space: BrowserSpace,
        tabID: TabID? = nil,
        adoptedConfiguration: WKWebViewConfiguration? = nil,
        extensionConfiguration: BrowserExtensionPageConfiguration? = nil
    ) -> BrowserPage {
        let interval = Self.lifecycleSignposter.beginInterval("Create Browser Page")
        defer {
            Self.lifecycleSignposter.endInterval("Create Browser Page", interval)
        }

        let contentRuleLists = contentRuleLists(for: space)
        let page = BrowserPage(
            configuration: adoptedConfiguration
                ?? extensionConfiguration?.webViewConfiguration
                ?? BrowserPageConfiguration.make(
                    for: space.profile,
                    websiteDataStore: websiteDataStore(for: space.profile),
                    webExtensionController: browsingMode.isPrivate
                        ? nil
                        : extensionControllerPool.controller(for: space),
                    contentRuleLists: contentRuleLists
                ),
            dialogPresenter: dialogPresenter,
            downloadCenter: downloadCenter,
            permissionCenter: permissionCenter,
            hostedNotificationCenter: extensionConfiguration == nil
                ? hostedNotificationCenter
                : nil,
            serverTrustOverrides: serverTrustOverrides,
            mediaSessionStore: tabID == nil ? nil : mediaSessionStore,
            spaceID: space.id,
            profileID: space.profile.id,
            spaceName: space.name,
            extensionBaseURL: extensionConfiguration?.baseURL,
            extensionContext: extensionConfiguration?.context,
            contentRuleLists: contentRuleLists,
            externallyConnectableMatchPatterns: browsingMode.isPrivate
                ? []
                : extensionControllerPool.externallyConnectableMatchPatterns(
                    in: space.id
                ),
            ownsUserContentController: adoptedConfiguration == nil
                && extensionConfiguration == nil,
            allowsCredentialAccess: !browsingMode.isPrivate,
            isCredentialAccessEnabled:
                space.credentialPreferences.isEnabled,
            defaultPageZoom: pageZoomPreferences.defaultZoom,
            allowsChromeWebStoreExtensions: !browsingMode.isPrivate,
            prepareChromeWebStoreExtension: {
                [chromeWebStoreProvider] item in
                try await chromeWebStoreProvider.candidate(for: item)
            },
            installChromeWebStoreExtension: {
                [extensionControllerPool] candidate in
                try await extensionControllerPool
                    .installChromeWebStoreExtension(candidate, in: space)
            },
            allowsMozillaAddonsExtensions: !browsingMode.isPrivate,
            prepareMozillaAddonsExtension: {
                [mozillaAddonsProvider] item in
                try await mozillaAddonsProvider.candidate(for: item)
            },
            installMozillaAddonsExtension: {
                [extensionControllerPool] candidate in
                try await extensionControllerPool
                    .installMozillaAddonsExtension(candidate, in: space)
            },
            loadHTTPAuthenticationCredential: { [loadHTTPAuthenticationCredential] protectionSpace in
                try await loadHTTPAuthenticationCredential(protectionSpace, space.id)
            },
            saveHTTPAuthenticationCredential: { [saveHTTPAuthenticationCredential] request in
                try await saveHTTPAuthenticationCredential(request, space.id)
            },
            openNewTab: openNewTab,
            openModifiedLink: { [weak self] url, spaceID, selecting in
                self?.openModifiedLink(url, in: spaceID, selecting: selecting)
            },
            openPeek: openPeek,
            splitLinkHost: splitLinkHost,
            linkDestinationHost: linkDestinationHost,
            extensionWebpageMenuItems: {
                [extensionWebpageMenuProvider] context in
                guard let tabID else { return [] }
                return extensionWebpageMenuProvider.items(
                    for: tabID,
                    in: space.id,
                    context: context
                )
            }
        )
        page.host = self
        return page
    }

    private func tabID(for page: BrowserPage) -> TabID? {
        pages.first { $0.value === page }?.key
    }

    private func releaseSuspendedPages(for tabID: TabID) {
        clearRuntimeNavigation(for: tabID)
        for page in suspendedPagesByTabID.removeValue(forKey: tabID) ?? [] {
            page.prepareForSpaceDeletion()
        }
    }

    private func clearRuntimeNavigation(for tabID: TabID) {
        runtimeBackPagesByTabID[tabID] = nil
        runtimeForwardPagesByTabID[tabID] = nil
    }

    private func runtimeHistory(
        local: [BrowserNavigationHistoryItem],
        crossingTo page: BrowserPage?,
        continuation: KeyPath<BrowserPage, [BrowserNavigationHistoryItem]>
    ) -> [BrowserNavigationHistoryItem] {
        guard let page,
            let url = page.url ?? page.webView.url
        else { return local }
        var history = local
        history.append(
            BrowserNavigationHistoryItem(
                depth: history.count + 1,
                title: page.title.isEmpty ? url.absoluteString : page.title,
                url: url
            )
        )
        history.append(
            contentsOf: page[keyPath: continuation].map { item in
                BrowserNavigationHistoryItem(
                    depth: history.count + item.depth,
                    title: item.title,
                    url: item.url
                )
            }
        )
        return history
    }

    @discardableResult
    private func crossRuntimeHistoryBackward(for tabID: TabID) -> BrowserPage? {
        guard let destinationPage = runtimeBackPagesByTabID[tabID],
            let currentPage = swapActiveRuntime(
                for: tabID,
                to: destinationPage
            )
        else { return nil }
        runtimeBackPagesByTabID[tabID] = nil
        runtimeForwardPagesByTabID[tabID] = currentPage
        residencyRevision &+= 1
        return destinationPage
    }

    @discardableResult
    private func crossRuntimeHistoryForward(for tabID: TabID) -> BrowserPage? {
        guard let destinationPage = runtimeForwardPagesByTabID[tabID],
            let currentPage = swapActiveRuntime(
                for: tabID,
                to: destinationPage
            )
        else { return nil }
        runtimeForwardPagesByTabID[tabID] = nil
        runtimeBackPagesByTabID[tabID] = currentPage
        residencyRevision &+= 1
        return destinationPage
    }

    /// Swaps one retained configuration back into the live tab without loading
    /// either page. The caller owns the history direction and observation bump.
    private func swapActiveRuntime(
        for tabID: TabID,
        to destinationPage: BrowserPage
    ) -> BrowserPage? {
        guard let currentPage = pages[tabID],
            var suspendedPages = suspendedPagesByTabID[tabID],
            let index = suspendedPages.firstIndex(where: {
                $0 === destinationPage
            })
        else { return nil }
        suspendedPages.remove(at: index)
        suspendedPages.append(currentPage)
        suspendedPagesByTabID[tabID] = suspendedPages
        pages[tabID] = destinationPage
        return currentPage
    }

    private func contentRuleLists(for space: BrowserSpace) -> [WKContentRuleList] {
        guard space.browsingPreferences.contentBlockingPolicy == .balanced else {
            return []
        }
        return balancedContentRuleLists ?? []
    }

    private func websiteDataStore(for profile: BrowsingProfile) -> WKWebsiteDataStore? {
        guard usesEphemeralWebsiteDataStores else { return nil }
        if let dataStore = ephemeralDataStores[profile.id] {
            return dataStore
        }
        let dataStore = WKWebsiteDataStore.nonPersistent()
        ephemeralDataStores[profile.id] = dataStore
        return dataStore
    }

    private func loadInitialURL(for tab: BrowserTab, into page: BrowserPage) {
        // WebKit owns an adopted popup's first navigation. Loading it here would
        // replace the document `window.open()` handed to the opener.
        guard !page.isAwaitingPopupNavigation else { return }
        guard page.url == nil, let url = tab.url else { return }
        let interval = Self.lifecycleSignposter.beginInterval("Start Initial Navigation")
        // Restoring WebKit's session state performs its own navigation, so it
        // replaces the plain load rather than preceding it. Anything WebKit will
        // not take — absent, written by another OS build, or no longer describing
        // where the tab points — falls through to the plain load.
        if let state = archivedInteractionState(
            for: tab,
            profileID: page.profileID,
            expecting: url
        ), page.restoreInteractionState(state, expecting: url) {
            Self.lifecycleSignposter.endInterval("Start Initial Navigation", interval)
            return
        }
        page.load(url)
        Self.lifecycleSignposter.endInterval("Start Initial Navigation", interval)
    }

    private func reload(
        _ mode: BrowserPageReloadMode,
        selectedBy session: BrowserSession
    ) {
        guard let tab = session.selectedTab,
            let space = session.selectedSpace
        else { return }
        let residentPage = pages[tab.id]
        let canReloadResidentPage =
            residentPage?.spaceID == space.id
            && residentPage?.profileID == space.profile.id
            && residentPage?.url != nil

        select(session: session)

        guard canReloadResidentPage else {
            // Selection creates a missing WebView and starts its saved URL.
            // Do not immediately issue a second navigation for that recovery.
            return
        }
        activePage?.performReload(mode)
    }

    /// Focuses a tab that is already on screen, or brings one on screen beside
    /// the cards already there.
    ///
    /// Popup adoption and extension selection reach focus without going through
    /// `select`, one frame ahead of the store-driven reselection that settles
    /// the presented set properly. Adding the tab here rather than replacing
    /// the set is what keeps that frame from rendering a card with no page.
    private func activate(_ tabID: TabID, at time: Date) {
        var presented = presentedTabIDs
        if !presented.contains(tabID) {
            presented.append(tabID)
        }
        activate(tabID, presenting: presented, at: time)
    }

    /// Puts `presentedTabIDs` on screen in order with `tabID` focused.
    ///
    /// Idle time is a property of being off screen rather than of being
    /// unfocused: every presented card is cleared, and only a tab the new set
    /// leaves behind starts counting as inactive.
    private func activate(
        _ tabID: TabID,
        presenting presentedTabIDs: [TabID],
        at time: Date
    ) {
        prepareFocusTransition(to: pages[tabID])
        let departed = Set(self.presentedTabIDs).subtracting(presentedTabIDs)
        for departedTabID in departed where pages[departedTabID] != nil {
            inactiveSinceByTabID[departedTabID] = time
        }
        if let activeTabID, !presentedTabIDs.contains(activeTabID),
            pages[activeTabID] != nil
        {
            inactiveSinceByTabID[activeTabID] = time
        }
        for presentedTabID in presentedTabIDs {
            inactiveSinceByTabID[presentedTabID] = nil
        }
        self.presentedTabIDs = presentedTabIDs
        activeTabID = tabID
    }

    private func prepareFocusTransition(to destination: BrowserPage?) {
        let source = activePage
        guard source !== destination else { return }
        guard let source, let destination else {
            source?.focusRestoration.invalidate()
            destination?.focusRestoration.invalidate()
            return
        }

        // Each resident page owns its own responder. Switching Spaces does
        // not change that ownership; moving a tab or replacing its profile
        // recreates the page and invalidates the old responder separately.
        source.focusRestoration.captureBeforeDeparture()
        destination.focusRestoration.requestRestoration(
            displacing: source.webView
        )
    }

    @discardableResult
    private func releasePages(
        for tabIDs: Set<TabID>
    ) -> [BrowserSpaceDataReleaseProbe] {
        var releasedAnyPage = false
        var probes: [BrowserSpaceDataReleaseProbe] = []
        for tabID in tabIDs {
            if let page = pages.removeValue(forKey: tabID) {
                forgetBackgroundPageObservation(for: tabID)
                probes.append(BrowserSpaceDataReleaseProbe(page))
                page.prepareForSpaceDeletion()
                releasedAnyPage = true
            }
            if let suspendedPages = suspendedPagesByTabID.removeValue(
                forKey: tabID
            ) {
                for page in suspendedPages {
                    probes.append(BrowserSpaceDataReleaseProbe(page))
                    page.prepareForSpaceDeletion()
                }
                releasedAnyPage = true
            }
        }
        if releasedAnyPage { residencyRevision &+= 1 }
        inactiveSinceByTabID = inactiveSinceByTabID.filter {
            !tabIDs.contains($0.key)
        }
        if let activeTabID, tabIDs.contains(activeTabID) {
            self.activeTabID = nil
        }
        // Locking a Space reaches here, so a released page never stays a card.
        presentedTabIDs.removeAll { tabIDs.contains($0) }
        return probes
    }

    /// Releases the pages memory pressure can afford to take back.
    ///
    /// Every presented card is ineligible, not only the focused one: unloading
    /// a web view the person is looking at is never a saving worth making.
    private func releaseInactivePages(for level: BrowserMemoryPressureLevel) async {
        let candidates = inactiveSinceByTabID.compactMap {
            tabID,
            inactiveSince -> (tabID: TabID, inactiveSince: Date, page: BrowserPage)? in
            guard !presentedTabIDs.contains(tabID), let page = pages[tabID] else {
                return nil
            }
            return (tabID: tabID, inactiveSince: inactiveSince, page: page)
        }.sorted {
            if $0.inactiveSince != $1.inactiveSince {
                return $0.inactiveSince < $1.inactiveSince
            }
            return $0.tabID.rawValue.uuidString < $1.tabID.rawValue.uuidString
        }

        var eligibleTabIDs: [TabID] = []
        for candidate in candidates {
            guard !Task.isCancelled else { return }
            // `BrowserPageResidencyDecision.isSelected` now means "is
            // presented" — a card of the split on screen, focused or not.
            // Every candidate here is off screen, so it is answered `false`.
            // The name stays until the decision type is revisited.
            let runtimePages =
                [candidate.page]
                + (suspendedPagesByTabID[candidate.tabID] ?? [])
            var allRuntimesAllowAutomaticUnload = true
            for page in runtimePages {
                let decision = await residencyDecisionProvider(page, false)
                if !decision.allowsAutomaticUnload {
                    allRuntimesAllowAutomaticUnload = false
                    break
                }
            }
            // Re-checked after the await: a page can be selected back onto the
            // screen while WebKit is answering for it.
            guard pages[candidate.tabID] === candidate.page,
                !presentedTabIDs.contains(candidate.tabID),
                allRuntimesAllowAutomaticUnload
            else { continue }
            eligibleTabIDs.append(candidate.tabID)
        }
        let releaseLimit = BrowserMemoryPressureReleasePolicy.releaseLimit(
            for: level,
            eligiblePageCount: eligibleTabIDs.count,
            platform: .desktop
        )
        for tabID in eligibleTabIDs.prefix(releaseLimit) {
            evictPage(tabID)
        }
    }

    private func evictPage(_ tabID: TabID, preservingTabState: Bool = true) {
        if preservingTabState {
            archiveTabState(for: tabID)
        }
        guard let page = pages.removeValue(forKey: tabID) else { return }
        forgetBackgroundPageObservation(for: tabID)
        page.prepareForSpaceDeletion()
        releaseSuspendedPages(for: tabID)
        residencyRevision &+= 1
        inactiveSinceByTabID[tabID] = nil
    }

    private func releaseTransientPages(for level: BrowserMemoryPressureLevel) {
        pruneTransientLeases()
        for lease in transientLeases.values.compactMap(\.value) {
            guard level == .critical || !lease.isActive else { continue }
            lease.releaseForMemoryPressure()
        }
    }

    @discardableResult
    private func releaseTransientPages(
        in spaceID: SpaceID
    ) -> [BrowserSpaceDataReleaseProbe] {
        pruneTransientLeases()
        let matching = transientLeases.filter { $0.value.value?.spaceID == spaceID }
        var probes: [BrowserSpaceDataReleaseProbe] = []
        for (id, weakLease) in matching {
            if let page = weakLease.value?.page {
                probes.append(BrowserSpaceDataReleaseProbe(page))
            }
            weakLease.value?.release()
            transientLeases.removeValue(forKey: id)
        }
        return probes
    }

    private func releaseAllTransientPages() {
        for lease in transientLeases.values.compactMap(\.value) {
            lease.release()
        }
        transientLeases.removeAll()
    }

    private func releaseExtensionOffscreenDocuments(in spaceID: SpaceID) {
        closeExtensionSidebars(inSpace: spaceID)
        let matchingKeys = extensionOffscreenDocuments.keys.filter {
            $0.spaceID == spaceID
        }
        for key in matchingKeys {
            extensionOffscreenDocuments.removeValue(forKey: key)?.close()
        }
    }

    private func releaseAllExtensionOffscreenDocuments() {
        closeExtensionSidebars()
        for document in extensionOffscreenDocuments.values {
            document.close()
        }
        extensionOffscreenDocuments.removeAll()
    }

    private func pruneTransientLeases() {
        transientLeases = transientLeases.filter { $0.value.value != nil }
    }

    private func installMemoryPressureSource() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            // `dispatch_source_get_data` is only defined while this handler is
            // running: read after a hop it answers zero, and critical pressure
            // would forever look like a warning. The source runs on the main
            // queue, so the event is captured and handled without one.
            MainActor.assumeIsolated {
                guard let self, let source = self.memoryPressureSource else { return }
                self.handleMemoryPressureEvent(source.data)
            }
        }
        memoryPressureSource = source
        source.resume()
    }
}

@MainActor
private final class BrowserExtensionOffscreenDocument: NSObject,
    WKNavigationDelegate
{
    /// This document's `runtime.getContexts` identity, and the URL it holds.
    /// Both live and die with the document, as a Chrome context ID does.
    let contextID = UUID().uuidString
    private(set) var url: URL?
    private let webView: WKWebView
    private var loadContinuation: CheckedContinuation<Void, any Error>?

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.isInspectable = true
    }

    func load(_ url: URL) async throws {
        guard loadContinuation == nil else {
            throw BrowserExtensionOffscreenDocumentError.alreadyExists
        }
        self.url = url
        try await withCheckedThrowingContinuation { continuation in
            loadContinuation = continuation
            guard webView.load(URLRequest(url: url)) != nil else {
                finishLoading(
                    .failure(BrowserExtensionOffscreenDocumentError.unavailable)
                )
                return
            }
        }
    }

    func close() {
        webView.stopLoading()
        finishLoading(
            .failure(BrowserExtensionOffscreenDocumentError.unavailable)
        )
        webView.navigationDelegate = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        finishLoading(.success(()))
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: any Error
    ) {
        finishLoading(
            .failure(
                BrowserExtensionOffscreenDocumentError.loadFailed(
                    error.localizedDescription
                )
            )
        )
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        finishLoading(
            .failure(
                BrowserExtensionOffscreenDocumentError.loadFailed(
                    error.localizedDescription
                )
            )
        )
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finishLoading(
            .failure(
                BrowserExtensionOffscreenDocumentError.loadFailed(
                    "The extension web content process stopped."
                )
            )
        )
    }

    private func finishLoading(_ result: Result<Void, any Error>) {
        guard let loadContinuation else { return }
        self.loadContinuation = nil
        loadContinuation.resume(with: result)
    }
}
