import AppKit
import Dispatch
import Foundation
import Observation
import WebKit
import os

@Observable
@MainActor
final class BrowserPagePool:
    BrowserSpaceDataDeleting,
    BrowserPageHosting,
    BrowserDefaultPageZoomObserving
{

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
    private(set) var activeTabID: TabID? {
        willSet {
            if let activeTabID, activeTabID != newValue,
                tabRuntimes[activeTabID]?.presentationWindowID == windowID,
                !runtimeStore.isPresented(activeTabID, outside: windowID)
            {
                activePage?.translation.suspend()
            }
        }
    }

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
    private(set) var presentedTabIDs: [TabID] = [] {
        didSet { runtimeStore.updatePresentation(of: self) }
    }
    private(set) var residencyRevision: Int {
        get { runtimeStore.revision }
        set { runtimeStore.revision = newValue }
    }
    let runtimeStore: BrowserPageRuntimeStore
    let windowID: BrowserWindowID
    @ObservationIgnored private weak var presentationWindow: NSWindow?
    private(set) var isWindowFocused = true
    var publishesPageMetadataCentrally: Bool { runtimeStore.publishesPageMetadataCentrally }
    var contentBlockingErrorDescription: String? { contentBlocking.errorDescription }
    let downloadCenter: BrowserDownloadCenter
    /// Mirrors the runtime's console capture: web pages then report their
    /// calls into an installed extension to the diagnostics log.
    let permissionCenter: BrowserSitePermissionCenter
    var serverTrustOverrides: BrowserServerTrustOverrideStore { profileDataStores.serverTrustOverrides }

    /// Each tab owns its current and suspended configurations, including the
    /// history links that bridge ordinary pages and extension origins.
    private var tabRuntimes: [TabID: BrowserTabRuntime] {
        get { runtimeStore.runtimes }
        set { runtimeStore.runtimes = newValue }
    }
    private var inactiveSinceByTabID: [TabID: Date] {
        get { runtimeStore.inactiveSinceByTabID }
        set { runtimeStore.inactiveSinceByTabID = newValue }
    }
    @ObservationIgnored private let profileDataStores: BrowserPageProfileDataStores
    private var ephemeralDataStores: [UUID: WKWebsiteDataStore] {
        get { profileDataStores.ephemeral }
        set { profileDataStores.ephemeral = newValue }
    }
    @ObservationIgnored private let residencyDecisionProvider: ResidencyDecisionProvider
    private var memoryPressureReleaseTask: Task<Void, Never>? {
        get { runtimeStore.memoryPressureTask }
        set { runtimeStore.memoryPressureTask = newValue }
    }
    @ObservationIgnored private let monitorsMemoryPressure: Bool
    @ObservationIgnored private let contentRuleListProvider: any BrowserContentRuleListProviding
    @ObservationIgnored private let browsingMode: BrowserBrowsingMode
    @ObservationIgnored private let usesEphemeralWebsiteDataStores: Bool
    @ObservationIgnored private let pageZoomPreferences: BrowserDefaultPageZoomStore
    @ObservationIgnored private let dialogPresenter: BrowserDialogPresenter
    @ObservationIgnored private let popupTabHost: BrowserPopupTabHost
    @ObservationIgnored private let openNewTab: (URL) -> Void
    @ObservationIgnored private let openModifiedLink: ModifiedLinkOpener
    @ObservationIgnored private let backgroundPageDidUpdate: BackgroundPageUpdateHandler
    @ObservationIgnored private let openPeek: (BrowserPeekRequest) -> Void
    @ObservationIgnored private let handleLinkDrag: (BrowserPeekInteractionEvent) -> Void
    @ObservationIgnored private let splitLinkHost: BrowserSplitLinkHost
    @ObservationIgnored let linkDestinationHost: BrowserLinkDestinationHost
    @ObservationIgnored private let hostedNotificationCenter: (any BrowserHostedWebNotificationCentering)?
    @ObservationIgnored private let mediaSessionStore: BrowserMediaSessionStore?
    @ObservationIgnored private var selectPictureInPictureSource: (BrowserTabRuntimeAssignment) -> BrowserSession? = {
        _ in nil
    }
    @ObservationIgnored private let activateHostedNotificationSource: (SpaceID, TabID) -> Void
    @ObservationIgnored private let loadHTTPAuthenticationCredential: HTTPAuthenticationCredentialLoader
    @ObservationIgnored private let saveHTTPAuthenticationCredential: HTTPAuthenticationCredentialSaver
    @ObservationIgnored private let websiteDataStoreRemover: any BrowserWebsiteDataStoreRemoving
    @ObservationIgnored private let contentBlocking: BrowserContentBlockingController
    @ObservationIgnored private var memoryPressureSource: (any DispatchSourceMemoryPressure)?
    private var memoryPressureCoalescer: BrowserMemoryPressureCoalescer {
        get { runtimeStore.memoryPressureCoalescer }
        set { runtimeStore.memoryPressureCoalescer = newValue }
    }
    @ObservationIgnored private var peekPageLeases:
        [UUID: (request: BrowserPeekRequest, lease: BrowserTransientPageLease)] = [:]
    @ObservationIgnored private var transientLeases: [UUID: WeakBrowserTransientPageLease] = [:]
    private var spacesReleasingData: Set<SpaceID> {
        get { runtimeStore.spacesReleasingData }
        set { runtimeStore.spacesReleasingData = newValue }
    }
    private var spacesDeletingData: Set<SpaceID> {
        get { runtimeStore.spacesDeletingData }
        set { runtimeStore.spacesDeletingData = newValue }
    }
    /// Where unloaded tabs leave their WebKit session state. Its archive is nil
    /// for a private pool, even if an archive is handed in.
    @ObservationIgnored private let tabState: BrowserTabStateCoordinator
    @ObservationIgnored private var backgroundPageSnapshots: [TabID: BrowserBackgroundPageSnapshot] = [:]
    @ObservationIgnored private var backgroundPageAssignments: [TabID: BrowserSpaceRuntimeAssignment] = [:]

    init(
        runtimeStore: BrowserPageRuntimeStore? = nil,
        windowID: BrowserWindowID = BrowserWindowID(),
        profileDataStores: BrowserPageProfileDataStores? = nil,
        monitorsMemoryPressure: Bool = false,
        browsingMode: BrowserBrowsingMode = .standard,
        usesEphemeralWebsiteDataStores: Bool =
            BrowserLaunchIsolationPolicy.usesEphemeralProfileStorage(.current),
        pageZoomPreferences: BrowserDefaultPageZoomStore = .shared,
        permissionCenter: BrowserSitePermissionCenter = BrowserSitePermissionCenter(),
        hostedNotificationCenter:
            (any BrowserHostedWebNotificationCentering)? = nil,
        mediaSessionStore: BrowserMediaSessionStore? = nil,
        downloadCenter: BrowserDownloadCenter? = nil,
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
        handleLinkDrag: @escaping (BrowserPeekInteractionEvent) -> Void = { _ in },
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
        let owner =
            runtimeStore
            ?? BrowserPageRuntimeStore(
                archive: self.usesEphemeralWebsiteDataStores ? nil : tabStateArchive
            )
        self.runtimeStore = owner
        self.windowID = windowID
        self.profileDataStores = profileDataStores ?? BrowserPageProfileDataStores()
        self.monitorsMemoryPressure = monitorsMemoryPressure
        self.contentRuleListProvider = contentRuleListProvider
        tabState = owner.tabState
        self.permissionCenter = permissionCenter
        self.hostedNotificationCenter = hostedNotificationCenter
        self.mediaSessionStore = browsingMode.isPrivate ? nil : mediaSessionStore
        self.dialogPresenter = dialogPresenter
        self.popupTabHost = popupTabHost
        self.loadHTTPAuthenticationCredential = loadHTTPAuthenticationCredential
        self.saveHTTPAuthenticationCredential = saveHTTPAuthenticationCredential
        self.websiteDataStoreRemover = websiteDataStoreRemover
        contentBlocking = BrowserContentBlockingController(provider: contentRuleListProvider)
        self.openNewTab = openNewTab
        self.openModifiedLink = openModifiedLink
        self.backgroundPageDidUpdate = backgroundPageDidUpdate
        self.openPeek = openPeek
        self.handleLinkDrag = handleLinkDrag
        self.splitLinkHost = splitLinkHost
        self.linkDestinationHost = linkDestinationHost
        self.activateHostedNotificationSource = activateHostedNotificationSource
        self.downloadCenter =
            downloadCenter
            ?? BrowserDownloadCenter(
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
                approveEngineDownload: { filename, message in
                    await dialogPresenter.approveEngineDownload(filename: filename, message: message)
                },
                permissionCenter: permissionCenter
            )
        if monitorsMemoryPressure {
            installMemoryPressureSource()
        }
        pageZoomPreferences.register(self)
        self.runtimeStore.register(self)
    }

    deinit {
        memoryPressureSource?.cancel()
    }

    var nativeTabs: BrowserNativeTabStore { runtimeStore.nativeTabs }

    func bindNativeWindow(_ window: NSWindow?) {
        presentationWindow = window
    }

    func setWindowFocused(_ focused: Bool) {
        isWindowFocused = focused
        if focused { runtimeStore.focus(self) }
    }

    func releaseWindowPresentation() {
        presentationWindow = nil
        activeTabID = nil
        presentedTabIDs = []
        runtimeStore.unregister(self)
    }

    func isMirroringPage(for tabID: TabID) -> Bool {
        _ = residencyRevision
        guard presentedTabIDs.contains(tabID), let runtime = tabRuntimes[tabID] else { return false }
        return runtime.presentationWindowID != nil && runtime.presentationWindowID != windowID
    }

    func mirroredPageSnapshot(for tabID: TabID) -> NSImage? {
        _ = residencyRevision
        return tabRuntimes[tabID]?.snapshot
    }

    func claimPresentedPage(for tabID: TabID) {
        runtimeStore.claim(tabID, for: self)
    }

    func removeTransferredPresentation(_ tabID: TabID) {
        presentedTabIDs.removeAll { $0 == tabID }
        if activeTabID == tabID { activeTabID = nil }
        forgetBackgroundPageObservation(for: tabID)
    }

    /// The caller commits the matching model move in the same main-actor turn.
    /// No load, teardown or archive may occur while transferring the runtime.
    func transferTabRuntime(
        from source: BrowserPagePool,
        matching assignment: BrowserTabRuntimeAssignment,
        as tab: BrowserTab,
        in space: BrowserSpace
    ) -> Bool {
        guard canTransferTabRuntime(from: source, matching: assignment, as: tab, in: space) else { return false }
        guard source.runtimeStore !== runtimeStore else { return true }
        if source.nativeTabs.contains(assignment) {
            guard source.nativeTabs.transfer(matching: assignment, to: nativeTabs) else { return false }
            source.runtimeStore.removePresentation(of: tab.id)
            return true
        }
        guard let runtime = source.tabRuntimes[tab.id] else {
            if let url = tab.url,
                let state = source.archivedInteractionState(
                    for: tab, spaceID: space.id, profileID: space.profile.id, expecting: url)
            {
                tabState.prepareCopy(state, url: url, for: assignment)
            }
            source.tabState.discardState(matching: assignment)
            source.runtimeStore.removePresentation(of: tab.id)
            return true
        }
        source.tabRuntimes.removeValue(forKey: tab.id)
        source.inactiveSinceByTabID[tab.id] = nil
        source.tabState.discardState(matching: assignment)
        source.runtimeStore.removePresentation(of: tab.id)
        source.residencyRevision &+= 1
        runtime.presentationWindowID = nil
        runtimeStore.install(runtime, for: tab.id, from: self)
        for page in runtime.allPages {
            page.updateNavigationContext(
                tab: tab,
                automaticallyOpensPeek: BrowserLinkPreferenceStore.shared.preferences.automaticallyOpensPeek)
        }
        residencyRevision &+= 1
        return true
    }

    func canTransferTabRuntime(
        from source: BrowserPagePool,
        matching assignment: BrowserTabRuntimeAssignment,
        as tab: BrowserTab,
        in space: BrowserSpace
    ) -> Bool {
        guard assignment.tabID == tab.id, assignment.spaceID == space.id,
            assignment.profileID == space.profile.id,
            !isRuntimeCreationBlocked(in: space.id),
            !source.isRuntimeCreationBlocked(in: space.id)
        else { return false }
        guard source.runtimeStore !== runtimeStore else { return true }
        guard tabRuntimes[tab.id] == nil, !nativeTabs.tabIDs.contains(tab.id) else { return false }
        if source.nativeTabs.tabIDs.contains(tab.id) { return source.nativeTabs.contains(assignment) }
        guard let runtime = source.tabRuntimes[tab.id] else { return true }
        return runtime.page.spaceID == space.id && runtime.page.profileID == space.profile.id
    }

    /// Temporary windows end the lifetime of their own workspace. Normal
    /// windows only call releaseWindowPresentation and retain shared pages.
    func closeWindowWorkspace() {
        releaseWindowPresentation()
        reconcile(validTabIDs: [])
        releaseAllTransientPages()
    }

    func setRuntimeCreationBlocked(_ blocked: Bool, in spaceID: SpaceID) {
        if blocked {
            runtimeStore.blockedSpaces.insert(spaceID)
            profileDataStores.blockedSpaces.insert(spaceID)
        } else {
            runtimeStore.blockedSpaces.remove(spaceID)
            profileDataStores.blockedSpaces.remove(spaceID)
        }
    }

    private func isRuntimeCreationBlocked(in spaceID: SpaceID) -> Bool {
        spacesReleasingData.contains(spaceID) || spacesDeletingData.contains(spaceID)
            || runtimeStore.blockedSpaces.contains(spaceID) || profileDataStores.blockedSpaces.contains(spaceID)
    }

    func bindRuntimeRouting(_ runtime: BrowserTabRuntime, tabID: TabID) {
        for page in runtime.allPages {
            #if CREST_CHROMIUM_HOST
            page.chromiumPage?.isPrivateBrowsing = browsingMode.isPrivate
            #endif
            page.host = self
            page.windowRouting?.pool = self
            page.downloadCenter = downloadCenter
            page.splitLinkHost = splitLinkHost
            page.linkDestinationHost = linkDestinationHost
        }
    }

    func publishRuntimePageUpdate(
        _ runtime: BrowserTabRuntime, tabID: TabID,
        previous: BrowserBackgroundPageSnapshot?, current: BrowserBackgroundPageSnapshot
    ) {
        let page = runtime.page
        let completedURL = current.completedNavigationCount > (previous?.completedNavigationCount ?? 0) ? page.url : nil
        let update = BrowserBackgroundPageUpdate(
            tabID: tabID,
            assignment: BrowserSpaceRuntimeAssignment(spaceID: page.spaceID, profileID: page.profileID),
            url: current.url, title: current.title, faviconData: current.faviconData, iconAccent: current.iconAccent,
            estimatedProgress: current.estimatedProgress, isLoading: current.isLoading,
            readerModeState: current.readerModeState, completedNavigationURL: completedURL,
            processTerminationCount: current.processTerminationCount)
        guard let session = backgroundPageDidUpdate(update) else { return }
        if completedURL != nil, let space = session.space(id: page.spaceID), space.profile.id == page.profileID {
            Task { @MainActor [weak self] in await self?.styleVisitedLinks(in: space) }
        }
    }

    func makeWindowPool(
        browser: BrowserStore,
        windowID: BrowserWindowID,
        sharesRuntimes: Bool,
        transientBrowsing: BrowserTransientBrowsingCoordinator,
        spaceAccess: BrowserSpaceAccessController
    ) -> BrowserPagePool {
        let owner = sharesRuntimes ? runtimeStore : BrowserPageRuntimeStore()
        owner.publishesPageMetadataCentrally = true
        let pool = BrowserPagePool(
            runtimeStore: owner, windowID: windowID, profileDataStores: profileDataStores,
            monitorsMemoryPressure: monitorsMemoryPressure, browsingMode: browsingMode,
            usesEphemeralWebsiteDataStores: usesEphemeralWebsiteDataStores,
            pageZoomPreferences: pageZoomPreferences,

            permissionCenter: permissionCenter,
            hostedNotificationCenter: hostedNotificationCenter, mediaSessionStore: mediaSessionStore,
            downloadCenter: downloadCenter,
            loadHTTPAuthenticationCredential: { [weak browser] protectionSpace, spaceID in
                try await browser?.httpAuthenticationCredential(for: protectionSpace, in: spaceID)
            },
            saveHTTPAuthenticationCredential: { [weak browser] request, spaceID in
                try await browser?.saveHTTPAuthenticationCredential(
                    username: request.username, password: request.password, protectionSpace: request.protectionSpace,
                    in: spaceID, replacing: request.replacing)
            },
            websiteDataStoreRemover: websiteDataStoreRemover, contentRuleListProvider: contentRuleListProvider,
            popupTabHost: browser.popupTabHost,
            openNewTab: { [weak browser] url in browser?.openNewTab(url: url) },
            openModifiedLink: { [weak browser] url, spaceID, selecting in
                guard let browser, let tabID = browser.openNewTab(url: url, in: spaceID, selecting: selecting),
                    let space = browser.session.space(id: spaceID),
                    let tab = space.tabs.first(where: { $0.id == tabID })
                else { return nil }
                return BrowserModifiedLinkRegistration(tab: tab, space: space, session: browser.session)
            },
            backgroundPageDidUpdate: { [weak browser] update in
                guard let browser else { return nil }
                browser.updateBackgroundPage(update)
                return browser.session
            },
            openPeek: { [weak transientBrowsing] in transientBrowsing?.presentPeek($0) },
            handleLinkDrag: { [weak transientBrowsing] in transientBrowsing?.handleLinkDrag($0) },
            splitLinkHost: browser.splitLinkHost,
            linkDestinationHost: BrowserLinkDestinationHost(browser: browser, spaceAccess: spaceAccess),
            activateHostedNotificationSource: { [weak browser] spaceID, tabID in
                browser?.selectSpace(spaceID)
                browser?.selectTab(tabID)
            },
            residencyDecisionProvider: residencyDecisionProvider)
        pool.connectPictureInPictureSourceSelection(to: browser, spaceAccess: spaceAccess)
        browser.tabLinkProvider = pool
        browser.tabCopying = pool
        pool.setWindowFocused(false)
        return pool
    }

    /// Connects a directly presented pool to the browser selection it owns.
    func connectPictureInPictureSourceSelection(
        to browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController
    ) {
        selectPictureInPictureSource = { [weak browser, weak spaceAccess] source in
            guard let browser, let spaceAccess,
                let space = BrowserSidebarAccessPolicy.unlockedSpace(
                    matching: BrowserSpaceRuntimeAssignment(spaceID: source.spaceID, profileID: source.profileID),
                    in: browser, accessController: spaceAccess),
                space.tabs.contains(where: { $0.id == source.tabID })
            else { return nil }
            browser.selectSpace(space.id)
            browser.selectTab(source.tabID)
            return browser.session
        }
    }

    var retainedTabIDs: Set<TabID> {
        _ = residencyRevision
        return Set(tabRuntimes.keys)
    }

    func containsResidentPage(for tabID: TabID) -> Bool {
        _ = residencyRevision
        return tabRuntimes[tabID]?.page != nil
    }

    func containsResidentPage(
        matching assignment: BrowserTabRuntimeAssignment
    ) -> Bool {
        residentPage(matching: assignment) != nil
    }

    /// Reads an already-resident page for its own Space's chrome without
    /// selecting or loading it. Web content hosts must use presentedPage.
    func residentPage(matching assignment: BrowserTabRuntimeAssignment) -> BrowserPage? {
        _ = residencyRevision
        guard let page = tabRuntimes[assignment.tabID]?.page,
            page.spaceID == assignment.spaceID,
            page.profileID == assignment.profileID
        else { return nil }
        return page
    }

    func siteThemeIconAccent(for tabID: TabID) -> BrowserTabIconAccent? {
        tabRuntimes[tabID]?.page.siteThemeIconAccent
    }

    func siteThemeIconAccent(
        matching assignment: BrowserTabRuntimeAssignment
    ) -> BrowserTabIconAccent? {
        guard let page = tabRuntimes[assignment.tabID]?.page,
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
        return tabRuntimes[activeTabID]?.page
    }

    /// The resident page of a presented card, or `nil` for a tab that is not
    /// on screen right now.
    ///
    /// Membership is checked rather than residency alone: a background tab can
    /// keep a resident page for as long as memory allows, and handing one to a
    /// card would put a second host on a web view that already has one.
    func presentedPage(for tabID: TabID) -> BrowserPage? {
        _ = residencyRevision
        guard presentedTabIDs.contains(tabID),
            let runtime = tabRuntimes[tabID],
            runtime.presentationWindowID == windowID
        else { return nil }
        return runtime.page
    }

    var canGoBack: Bool { activePage?.canGoBack == true }
    var canGoForward: Bool { activePage?.canGoForward == true }
    var backHistory: [BrowserNavigationHistoryItem] { activePage?.backHistory ?? [] }
    var forwardHistory: [BrowserNavigationHistoryItem] { activePage?.forwardHistory ?? [] }

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
    private func presentCards(
        tab: BrowserTab?,
        space: BrowserSpace?,
        at time: Date
    ) -> [(tab: BrowserTab, page: BrowserPage)] {
        let interval = Self.lifecycleSignposter.beginInterval("Select Browser Page")
        defer {
            Self.lifecycleSignposter.endInterval("Select Browser Page", interval)
        }

        guard let space, !isRuntimeCreationBlocked(in: space.id) else {
            deactivatePagePresentation(at: time)
            return []
        }
        guard let tab else {
            leavePagePresentation(at: time)
            return []
        }
        // Every member of the selected tab's split group is a live card, so
        // each one is built and started here. A card the person can see must
        // never wait for focus to load: lazy loading is for tabs off screen.
        let members = presentedMembers(for: tab, in: space)
        for member in members { nativeTabs.load(tab: member, space: space, at: time) }
        let memberPages = members.filter { $0.nativeContent == nil }.map {
            (tab: $0, page: page(for: $0, space: space))
        }
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
        _ request: URLRequest,
        in spaceID: SpaceID,
        selecting: Bool
    ) {
        guard let url = request.url,
            let registration = openModifiedLink(url, spaceID, selecting)
        else {
            return
        }
        let page = page(for: registration.tab, space: registration.space)
        observeBackgroundPage(
            page,
            for: registration.tab.id,
            in: registration.space
        )
        page.load(request)
        if selecting { select(session: registration.session) }
        reconcileCredentialAccess(in: registration.session)
    }

    private func observeBackgroundPage(
        _ page: BrowserPage,
        for tabID: TabID,
        in space: BrowserSpace
    ) {
        guard !publishesPageMetadataCentrally else { return }
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
        guard tabRuntimes[tabID]?.page === page,
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

        guard !publishesPageMetadataCentrally,
            previous != current, !presentedTabIDs.contains(tabID)
        else {
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
        startInitialNavigations(cards)
        reconcileCredentialAccess(in: session)
    }

    /// An unlocked empty Space or start page is an ordinary departure. Keep
    /// the same PiP lifecycle as switching between loaded tabs; security
    /// teardown uses deactivatePagePresentation instead.
    func leavePagePresentation(at time: Date = .now) {
        activate(nil, presenting: [], at: time)
    }

    /// Removes every rendered page from presentation without evicting their
    /// isolated WebKit runtimes. Re-selecting the tab restores the resident
    /// page, while protected content cannot remain visible behind a lock gate.
    ///
    /// All of it goes at once, not just the focused card: a Space locking with
    /// a split open has to take every card away, and half a split left on
    /// screen would be the privacy failure the gate exists to prevent.
    func deactivatePagePresentation(at time: Date = .now) {
        for runtime in tabRuntimes.values where runtime.presentationWindowID == windowID {
            runtime.page.pictureInPicture?.invalidate()
        }
        guard activeTabID != nil || !presentedTabIDs.isEmpty else { return }
        for tabID in presentedTabIDs where tabRuntimes[tabID]?.presentationWindowID == windowID {
            tabRuntimes[tabID]?.page.focusRestoration.invalidate()
        }
        for tabID in presentedTabIDs {
            inactiveSinceByTabID[tabID] = time
        }
        if let activeTabID, !presentedTabIDs.contains(activeTabID) {
            inactiveSinceByTabID[activeTabID] = time
        }
        activeTabID = nil
        presentedTabIDs = []
    }

    func prepareContentBlocking() async {
        await contentBlocking.prepare()
    }

    /// Reloads presented pages only when their Space's protection level changes.
    func reconcileContentBlocking(in session: BrowserSession) async {
        let update = await contentBlocking.reconcile(in: session)
        for (tabID, runtime) in tabRuntimes {
            let page = runtime.page
            let isPresentedPage = runtimeStore.presentedTabIDs.contains(tabID)
            page.applyContentBlocking(
                policy: update.policy(for: page.spaceID),
                balancedRuleLists: contentBlocking.balancedRuleLists ?? [],
                activation: update.activation(for: page.spaceID, isPresented: isPresentedPage)
            )
        }

        pruneTransientLeases()
        for lease in transientLeases.values.compactMap(\.value) {
            lease.applyContentBlocking(
                policy: update.policy(for: lease.spaceID),
                balancedRuleLists: contentBlocking.balancedRuleLists ?? []
            )
        }
    }

    /// Refreshes rule lists without reloading unchanged documents.
    func reloadContentBlocking(in session: BrowserSession) async {
        contentBlocking.invalidateRuleLists()
        await reconcileContentBlocking(in: session)
    }

    func reconcile(validTabIDs: Set<TabID>) {
        nativeTabs.reconcile(validTabIDs: validTabIDs)
        tabState.retainCopies(for: validTabIDs)
        let removedTabIDs = Set(tabRuntimes.keys).subtracting(validTabIDs)
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
        nativeTabs.reconcile(session: session)
        let reconciliation = BrowserPageReconciliation(
            session: session,
            residentPages: tabRuntimes.lazy.map { ($0.key, $0.value.page) }
        )
        tabState.retainCopies(matching: reconciliation.validAssignments)
        // Capture a closed tab's WebKit stack before releasing its page.
        for tabID in reconciliation.tabIDsToArchive {
            archiveTabState(for: tabID)
        }
        releasePages(for: reconciliation.invalidTabIDs)
        for context in reconciliation.navigationContexts {
            context.page.updateNavigationContext(
                tab: context.tab,
                automaticallyOpensPeek: BrowserLinkPreferenceStore.shared
                    .preferences.automaticallyOpensPeek
            )
        }
        tabState.prune(keeping: reconciliation.retainedTabIDsByProfileID)
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
        for page in tabRuntimes.values.lazy.map(\.page) {
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

    /// Writes out the engine session state of every resident page. The app calls
    /// this when a scene stops being active, so state survives a quit before an
    /// inactive page reaches its idle deadline.
    func archiveResidentTabStates() {
        guard tabState.archivesResidentPages else { return }
        for (tabID, runtime) in tabRuntimes
        where runtime.routingWindowID == windowID || !publishesPageMetadataCentrally {
            archiveTabState(for: tabID)
        }
    }

    func flushPendingTabStateWrites() async {
        await tabState.flushPendingWrites()
    }

    /// Capture stays on the main actor; the archive schedules disk writes.
    private func archiveTabState(for tabID: TabID) {
        guard let page = tabRuntimes[tabID]?.page else { return }
        tabState.archivePage(page, for: tabID)
    }

    private func archivedInteractionState(
        for tab: BrowserTab,
        spaceID: SpaceID,
        profileID: UUID,
        expecting url: URL,
        consumePendingCopy: Bool = true
    ) -> Data? {
        tabState.interactionState(
            for: BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: spaceID, profileID: profileID),
            expecting: url,
            consumePendingCopy: consumePendingCopy
        )
    }

    func reconcileTabIcons(in session: BrowserSession) {
        let tabsByID = Dictionary(
            uniqueKeysWithValues: session.spaces.flatMap { space in
                space.tabs.map { ($0.id, $0) }
            }
        )
        for (tabID, runtime) in tabRuntimes {
            let page = runtime.page
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
        await BrowserFaviconFallbackLoader.shared.removeAll(
            for: space.profile.id
        )
        // Deleting a Space deletes its WebKit data, so the archived session state
        // of its tabs goes with it: nothing may outlive the profile it describes.
        tabState.removeStates(profileID: space.profile.id)
        serverTrustOverrides.removeApprovals(for: space.profile.id)
        if !usesEphemeralWebsiteDataStores {
            try await websiteDataStoreRemover.removePersistentDataStore(
                for: space.profile
            )
        }
        permissionCenter.reset(spaceID: space.id)
    }

    func releaseWindowRuntime(for space: BrowserSpace) async {
        let nativeTabIDs = nativeTabs.tabIDs(in: space.id)
        nativeTabs.remove(in: space.id)
        guard spacesReleasingData.insert(space.id).inserted else { return }
        defer { spacesReleasingData.remove(space.id) }

        let tabIDs = Set(
            tabRuntimes.compactMap { tabID, runtime in
                runtime.page.spaceID == space.id || runtime.page.profileID == space.profile.id ? tabID : nil
            }
        ).union(nativeTabIDs)
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
        releasePages(for: Set(tabRuntimes.keys).union(nativeTabs.tabIDs))
        nativeTabs.reconcile(validTabIDs: [])
        releaseAllTransientPages()
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
            guard seen.insert(tabID).inserted, let page = tabRuntimes[tabID]?.page else {
                return false
            }
            return page.spaceID == space.id && page.profileID == space.profile.id
        }
    }

    func styleVisitedLinks(in space: BrowserSpace) async {
        for tabID in visitedLinkStylingTabIDs(in: space) {
            await tabRuntimes[tabID]?.page.styleVisitedLinks(history: space.history)
        }
    }

    func makePeekPageLease(
        request: BrowserPeekRequest,
        in space: BrowserSpace,
        onDownloadOnlyNavigation: @escaping () -> Void
    ) -> BrowserTransientPageLease? {
        guard request.assignment == BrowserSpaceRuntimeAssignment(space: space) else { return nil }
        if let entry = peekPageLeases[request.id], entry.request == request,
            case let lease = entry.lease, lease.assignment == request.assignment,
            lease.page != nil || lease.wasReleasedForMemoryPressure
        {
            return lease
        }
        peekPageLeases.removeValue(forKey: request.id)?.lease.release()
        let lease = makeTransientPageLease(
            url: request.url, in: space, opensModifiedLinksInForeground: true,
            onDownloadOnlyNavigation: onDownloadOnlyNavigation)
        if let lease { peekPageLeases[request.id] = (request, lease) }
        return lease
    }

    func retainPeekPages(for requests: [BrowserPeekRequest]) {
        for (id, entry) in peekPageLeases where !requests.contains(entry.request) {
            peekPageLeases.removeValue(forKey: id)?.lease.release()
        }
    }

    func makeTransientPageLease(
        url: URL,
        in space: BrowserSpace,
        opensModifiedLinksInForeground: Bool = false,
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
            let page = makePage(space: space)
            page.opensModifiedLinksInForeground = opensModifiedLinksInForeground
            return page
        }
        guard let initialPage = makeTransientPage() else { return nil }
        let lease = BrowserTransientPageLease(
            page: initialPage,
            url: url,
            contentBlockingPolicy:
                space.browsingPreferences.contentBlockingPolicy,
            balancedContentRuleLists: contentBlocking.balancedRuleLists ?? [],
            rebuild: makeTransientPage,
            userActivity: onUserActivity,
            onDownloadOnlyNavigation: onDownloadOnlyNavigation
        )
        transientLeases[lease.id] = WeakBrowserTransientPageLease(lease)
        return lease
    }

    @discardableResult
    func adoptTransientPage(
        _ lease: BrowserTransientPageLease,
        as tabID: TabID,
        in space: BrowserSpace
    ) -> Bool {
        guard !isRuntimeCreationBlocked(in: space.id),
            let page = lease.page
        else { return false }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard lease.assignment == assignment,
            page.spaceID == assignment.spaceID,
            page.profileID == assignment.profileID
        else { return false }
        // Move the renderer before Quick Window dismissal destroys its old
        // host. SwiftUI attaches the retained native view on a later update.
        guard page.pageEngine.transferOwnership(to: windowID) else { return false }
        guard lease.relinquishPage() === page else { return false }
        page.opensModifiedLinksInForeground = false
        transientLeases.removeValue(forKey: lease.id)
        retainResidentPage(page, for: tabID)
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
        !isRuntimeCreationBlocked(in: assignment.spaceID)
    }

    func navigatePopupInCurrentPage(
        _ request: URLRequest,
        opener: BrowserPage
    ) -> Bool {
        guard request.url != nil,
            !isRuntimeCreationBlocked(in: opener.spaceID),
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
    #if CREST_CHROMIUM_HOST
    func chromiumDownloadAssignment(pageID: String, profileID: UUID) -> BrowserSpaceRuntimeAssignment? {
        let pages = tabRuntimes.values.flatMap(\.allPages) + transientLeases.values.compactMap { $0.value?.page }
        guard let page = pages.first(where: { $0.chromiumPage?.id == pageID }),
            page.profileID == profileID, !isRuntimeCreationBlocked(in: page.spaceID) else { return nil }
        return BrowserSpaceRuntimeAssignment(spaceID: page.spaceID, profileID: page.profileID)
    }

    /// Retain Chromium's original WebContents, including its opener, history,
    /// JavaScript state and extension tab identity, in the shared tab runtime.
    func adoptChromiumPage(_ values: [String: Any]) -> Bool {
        guard let token = values["adoptionId"] as? String,
            let profile = (values["profileId"] as? String).flatMap(UUID.init(uuidString:)) else { return false }
        let sourceID = values["sourcePageId"] as? String
        let opener: BrowserPage?
        if let sourceID {
            opener = tabRuntimes.values.compactMap(\.page).first { $0.chromiumPage?.id == sourceID }
        } else {
            guard values["windowId"] as? String == windowID.rawValue.uuidString else { return false }
            opener = activePage
        }
        guard let opener, opener.profileID == profile,
            !isRuntimeCreationBlocked(in: opener.spaceID),
            let registration = popupTabHost.openTab(
                (values["url"] as? String).flatMap(URL.init(string:)), opener.spaceID,
                values["foreground"] as? Bool ?? true),
            registration.space.profile.id == profile else { return false }
        let page = makePage(space: registration.space, tabID: registration.tab.id)
        page.markOpenedAsPopup()
        page.updateNavigationContext(tab: registration.tab, automaticallyOpensPeek: false)
        guard page.chromiumPage?.adopt(token) == true else {
            page.prepareForSpaceDeletion()
            popupTabHost.closeTab(registration.tab.id, registration.space.id)
            return false
        }
        retainResidentPage(page, for: registration.tab.id)
        residencyRevision &+= 1
        if values["foreground"] as? Bool ?? true { activate(registration.tab.id, at: .now) }
        else { observeBackgroundPage(page, for: registration.tab.id, in: registration.space) }
        return true
    }
    #endif

    func adoptPopupWebView(
        configuration: WKWebViewConfiguration,
        requestedURL: URL?,
        opener: BrowserPage,
        selecting: Bool = true
    ) -> WKWebView? {
        guard tabID(for: opener) != nil,
            !isRuntimeCreationBlocked(in: opener.spaceID),
            let registration = popupTabHost.openTab(requestedURL, opener.spaceID, selecting),
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
        retainResidentPage(page, for: registration.tab.id)
        residencyRevision &+= 1
        if selecting {
            activate(registration.tab.id, at: .now)
        } else {
            observeBackgroundPage(page, for: registration.tab.id, in: registration.space)
        }
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
        if let tabID = tabID(for: page), tabRuntimes[tabID]?.page === page,
            !presentedTabIDs.contains(tabID),
            inactiveSinceByTabID[tabID] == nil
        {
            inactiveSinceByTabID[tabID] = .now
        }
        closeWebContentInitiatedPage(page)
    }

    func restorePictureInPictureSourcePage(_ page: BrowserPage) {
        guard page.pictureInPicture?.canRestoreSource == true,
            let tabID = tabID(for: page),
            tabRuntimes[tabID]?.routingWindowID == windowID,
            !isRuntimeCreationBlocked(in: page.spaceID),
            let window = presentationWindow,
            let session = selectPictureInPictureSource(
                BrowserTabRuntimeAssignment(tabID: tabID, spaceID: page.spaceID, profileID: page.profileID))
        else { return }
        // Claim the existing runtime and its split group through normal
        // selection. WebKit finishes returning the original video inline once
        // SwiftUI reattaches its view; never recreate or navigate the page here.
        setWindowFocused(true)
        select(session: session)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func activateNotificationSourcePage(_ page: BrowserPage) {
        guard let tabID = tabID(for: page) else { return }
        activateHostedNotificationSource(page.spaceID, tabID)
    }

    func routeHostedWebNotificationMessage(_ message: WKScriptMessage) {
        guard let sourceWebView = message.webView,
            let page = tabRuntimes.values.lazy.map(\.page).first(where: { $0.webView === sourceWebView })
        else { return }
        page.receiveHostedWebNotificationMessage(message)
    }

    func routeGeolocationMessage(_ message: WKScriptMessage) {
        guard let sourceWebView = message.webView,
            let page = tabRuntimes.values.lazy.map(\.page).first(where: { $0.webView === sourceWebView })
        else { return }
        page.receiveGeolocationMessage(message)
    }

    func routeBlockedPopupMessage(_ message: WKScriptMessage) {
        guard let sourceWebView = message.webView,
            let page = tabRuntimes.values.lazy.map(\.page).first(where: { $0.webView === sourceWebView })
        else { return }
        page.receiveBlockedPopupMessage(message)
    }

    func routeMediaSessionMessage(_ message: WKScriptMessage) {
        guard let sourceWebView = message.webView,
            let page = tabRuntimes.values.lazy.map(\.page).first(where: { $0.webView === sourceWebView })
        else { return }
        page.receiveMediaSessionMessage(message)
    }


    func goBack() { activePage?.goBack() }
    func goForward() { activePage?.goForward() }
    func goBack(to item: BrowserNavigationHistoryItem) { activePage?.goBack(toDepth: item.depth) }
    func goForward(to item: BrowserNavigationHistoryItem) { activePage?.goForward(toDepth: item.depth) }

    /// Explicit durable close differs from residency eviction only when the
    /// person chose to return to the saved URL on the next open.
    func closeDurablePage(_ assignment: BrowserTabRuntimeAssignment, discardState: Bool) -> Bool {
        guard !nativeTabs.tabIDs.contains(assignment.tabID) || nativeTabs.contains(assignment) else { return false }
        guard
            (tabRuntimes[assignment.tabID]?.page).map({
                $0.spaceID == assignment.spaceID && $0.profileID == assignment.profileID
            }) ?? true
        else { return false }
        unloadPage(for: assignment.tabID, preservingTabState: !discardState)
        if discardState { discardArchivedTabState(matching: assignment) }
        return true
    }

    func discardArchivedTabState(matching assignment: BrowserTabRuntimeAssignment) {
        tabState.discardState(matching: assignment)
    }

    func unloadPage(for tabID: TabID) {
        unloadPage(for: tabID, preservingTabState: true)
    }

    private func unloadPage(for tabID: TabID, preservingTabState: Bool) {
        if nativeTabs.tabIDs.contains(tabID) {
            nativeTabs.remove(tabID)
            runtimeStore.removePresentation(of: tabID)
        }
        // Archived before the page is torn down: a tab closed by hand can be
        // reopened, and a tab unloaded by hand is expected to come back where it
        // was left.
        if preservingTabState { archiveTabState(for: tabID) }
        guard let runtime = tabRuntimes.removeValue(forKey: tabID) else { return }
        forgetBackgroundPageObservation(for: tabID)
        runtime.prepareForRelease()
        inactiveSinceByTabID[tabID] = nil
        runtimeStore.removePresentation(of: tabID)
        residencyRevision &+= 1
    }

    @discardableResult
    func unloadPage(
        for tabID: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        if nativeTabs.contains(
            BrowserTabRuntimeAssignment(
                tabID: tabID, spaceID: assignment.spaceID, profileID: assignment.profileID))
        {
            unloadPage(for: tabID)
            return true
        }
        guard let page = tabRuntimes[tabID]?.page,
            page.spaceID == assignment.spaceID,
            page.profileID == assignment.profileID
        else { return false }
        unloadPage(for: tabID)
        return true
    }

    /// Releases a Space's resident pages without archiving them. Normal Space
    /// switching and locking preserve residency and do not call this teardown.
    func unloadPages(in spaceID: SpaceID) {
        let nativeTabIDs = nativeTabs.tabIDs(in: spaceID)
        nativeTabs.remove(in: spaceID)
        let tabIDs = Set(
            tabRuntimes.compactMap { tabID, runtime in
                let page = runtime.page
                return page.spaceID == spaceID ? tabID : nil
            }
        )
        _ = releasePages(for: tabIDs.union(nativeTabIDs))
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
        // A background Space can still remember its editor after departure.
        // Locking ends that focus session even though its pages stay resident.
        let retainedPages =
            tabRuntimes.values.flatMap(\.allPages)
            + transientLeases.values.compactMap { $0.value?.page }
        for page in retainedPages where page.spaceID == space.id {
            page.focusRestoration.invalidate()
            page.pictureInPicture?.invalidate()
        }
        if activePage?.spaceID == space.id
            || presentedTabIDs.contains(where: { tabRuntimes[$0]?.page.spaceID == space.id })
        {
            deactivatePagePresentation()
        }
        tabState.removeStates(profileID: space.profile.id)
    }

    func reloadOrStop(in session: BrowserSession) {
        reload(.standard, selectedBy: session)
    }

    func forceReload(in session: BrowserSession) {
        guard let tab = session.selectedTab,
            let space = session.selectedSpace
        else { return }
        let residentPage = tabRuntimes[tab.id]?.page
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
            tabRuntimes.values.flatMap(\.allPages)
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
        guard let page = tabRuntimes[tabID]?.page, let data = await page.pullFavicon() else {
            return nil
        }
        return (data, page.siteThemeIconAccent)
    }

    func pullFavicon(
        for tabID: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) async -> (data: Data, iconAccent: BrowserTabIconAccent?)? {
        guard let page = tabRuntimes[tabID]?.page,
            page.spaceID == assignment.spaceID,
            page.profileID == assignment.profileID,
            let data = await page.pullFavicon(),
            tabRuntimes[tabID]?.page === page
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
        for pool in runtimeStore.registeredPools { pool.releaseTransientPages(for: level) }
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
        if let existingPage = tabRuntimes[tab.id]?.page {
            if existingPage.spaceID == space.id,
                existingPage.profileID == space.profile.id
            {
                let page = existingPage
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
            tabState.removeState(
                profileID: existingPage.profileID,
                tabID: tab.id
            )
            tabRuntimes.removeValue(forKey: tab.id)?.prepareForRelease()
            forgetBackgroundPageObservation(for: tab.id)
            inactiveSinceByTabID[tab.id] = nil
        }
        let page = makePage(
            space: space,
            tabID: tab.id
        )
        page.updateNavigationContext(
            tab: tab,
            automaticallyOpensPeek: BrowserLinkPreferenceStore.shared
                .preferences.automaticallyOpensPeek
        )
        retainResidentPage(page, for: tab.id)
        residencyRevision &+= 1
        return page
    }

    /// Popups retain WebKit's configuration to preserve their opener and request.
    private func makePage(
        space: BrowserSpace,
        tabID: TabID? = nil,
        adoptedConfiguration: WKWebViewConfiguration? = nil
    ) -> BrowserPage {
        let interval = Self.lifecycleSignposter.beginInterval("Create Browser Page")
        defer {
            Self.lifecycleSignposter.endInterval("Create Browser Page", interval)
        }

        let contentRuleLists = contentRuleLists(for: space)
        let routing = BrowserPageWindowRouting(pool: self)
        let page = BrowserPage(
            configuration: adoptedConfiguration
                ?? BrowserPageConfiguration.make(
                    for: space.profile,
                    websiteDataStore: websiteDataStore(for: space.profile),
                    contentRuleLists: contentRuleLists
                ),
            dialogPresenter: dialogPresenter,
            downloadCenter: downloadCenter,
            permissionCenter: permissionCenter,
            hostedNotificationCenter: hostedNotificationCenter,
            serverTrustOverrides: serverTrustOverrides,
            mediaSessionStore: tabID == nil ? nil : mediaSessionStore,
            spaceID: space.id,
            profileID: space.profile.id,
            spaceName: space.name,
            contentRuleLists: contentRuleLists,
            ownsUserContentController: adoptedConfiguration == nil,
            allowsCredentialAccess: !browsingMode.isPrivate,
            isCredentialAccessEnabled:
                space.credentialPreferences.isEnabled,
            defaultPageZoom: pageZoomPreferences.defaultZoom,
            loadHTTPAuthenticationCredential: { [weak routing] protectionSpace in
                try await routing?.pool?.loadHTTPAuthenticationCredential(protectionSpace, space.id)
            },
            saveHTTPAuthenticationCredential: { [weak routing] request in
                try await routing?.pool?.saveHTTPAuthenticationCredential(request, space.id)
            },
            openNewTab: { [weak routing] url in routing?.pool?.openNewTab(url) },
            openModifiedLink: { [weak routing] url, spaceID, selecting in
                routing?.pool?.openModifiedLink(url, in: spaceID, selecting: selecting)
            },
            openPeek: { [weak routing] in routing?.pool?.openPeek($0) },
            handleLinkDrag: { [weak routing] in routing?.pool?.handleLinkDrag($0) },
            splitLinkHost: splitLinkHost,
            linkDestinationHost: linkDestinationHost
        )
        #if CREST_CHROMIUM_HOST
        page.chromiumPage?.isPrivateBrowsing = browsingMode.isPrivate
        #endif
        page.host = self
        page.windowRouting = routing
        return page
    }

    private func tabID(for page: BrowserPage) -> TabID? {
        tabRuntimes.first { $0.value.page === page }?.key
    }

    private func retainResidentPage(_ page: BrowserPage, for tabID: TabID) {
        if let runtime = tabRuntimes[tabID] {
            runtime.page = page
            runtime.observeCurrentPage()
        } else {
            runtimeStore.install(BrowserTabRuntime(page: page), for: tabID, from: self)
        }
    }

    private func contentRuleLists(for space: BrowserSpace) -> [WKContentRuleList] {
        contentBlocking.ruleLists(for: space.browsingPreferences.contentBlockingPolicy)
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
        guard page.url == nil, page.pendingNavigationURL == nil, let url = tab.url else { return }
        let interval = Self.lifecycleSignposter.beginInterval("Start Initial Navigation")
        // The adapter restores its own navigation state instead of a plain load.
        // Missing or incompatible archives fall back to the tab's current URL.
        if let state = archivedInteractionState(
            for: tab,
            spaceID: page.spaceID,
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
        let residentPage = tabRuntimes[tab.id]?.page
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
        _ tabID: TabID?,
        presenting presentedTabIDs: [TabID],
        at time: Date
    ) {
        prepareFocusTransition(to: tabID.flatMap { tabRuntimes[$0]?.page })
        let departed = Set(self.presentedTabIDs).subtracting(presentedTabIDs)
        // Only pages leaving the visible set qualify. Moving focus within a
        // split must not float a video that is still visible beside the tab.
        let departures = ([activeTabID].compactMap { $0 } + self.presentedTabIDs)
            .filter { departed.contains($0) }
        var requested: Set<TabID> = []
        for departedTabID in departures
        where requested.insert(departedTabID).inserted
            && !runtimeStore.isPresented(departedTabID, outside: windowID)
        {
            tabRuntimes[departedTabID]?.page.pictureInPicture?.leaveTab()
        }
        for arrivingTabID in presentedTabIDs where !self.presentedTabIDs.contains(arrivingTabID) {
            tabRuntimes[arrivingTabID]?.page.pictureInPicture?.returnToTab()
        }
        for departedTabID in departed where tabRuntimes[departedTabID]?.page != nil {
            inactiveSinceByTabID[departedTabID] = time
        }
        if let activeTabID, !presentedTabIDs.contains(activeTabID),
            tabRuntimes[activeTabID]?.page != nil
        {
            inactiveSinceByTabID[activeTabID] = time
        }
        for presentedTabID in presentedTabIDs {
            inactiveSinceByTabID[presentedTabID] = nil
        }
        activeTabID = tabID
        self.presentedTabIDs = presentedTabIDs
    }

    private func prepareFocusTransition(to destination: BrowserPage?) {
        let source = activePage
        guard source !== destination else { return }
        if let destination, !isWindowFocused,
            let runtime = tabRuntimes.values.first(where: { $0.page === destination }),
            let owner = runtime.presentationWindowID, owner != windowID
        {
            return
        }
        guard
            activeTabID.flatMap({ tabRuntimes[$0]?.presentationWindowID }) == windowID
                || source == nil
        else { return }
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
            displacing: source.nativeView
        )
    }

    @discardableResult
    private func releasePages(
        for tabIDs: Set<TabID>
    ) -> [BrowserSpaceDataReleaseProbe] {
        var releasedAnyPage = false
        var probes: [BrowserSpaceDataReleaseProbe] = []
        for tabID in tabIDs {
            let runtime = tabRuntimes.removeValue(forKey: tabID)
            runtimeStore.removePresentation(of: tabID)
            guard let runtime else { continue }
            forgetBackgroundPageObservation(for: tabID)
            probes.append(contentsOf: runtime.allPages.map { BrowserSpaceDataReleaseProbe($0) })
            runtime.prepareForRelease()
            releasedAnyPage = true
        }
        if releasedAnyPage { residencyRevision &+= 1 }
        inactiveSinceByTabID = inactiveSinceByTabID.filter { !tabIDs.contains($0.key) }
        if let activeTabID, tabIDs.contains(activeTabID) {
            self.activeTabID = nil
        }
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
            guard !runtimeStore.presentedTabIDs.contains(tabID), let page = tabRuntimes[tabID]?.page else {
                return nil
            }
            return (tabID: tabID, inactiveSince: inactiveSince, page: page)
        }.sorted {
            if $0.inactiveSince != $1.inactiveSince {
                return $0.inactiveSince < $1.inactiveSince
            }
            return $0.tabID.rawValue.uuidString < $1.tabID.rawValue.uuidString
        }

        var eligiblePages: [(tabID: TabID, page: BrowserPage?)] = []
        for candidate in candidates {
            guard !Task.isCancelled else { return }
            // `BrowserPageResidencyDecision.isSelected` now means "is
            // presented" — a card of the split on screen, focused or not.
            // Every candidate here is off screen, so it is answered `false`.
            // The name stays until the decision type is revisited.
            let decision = await residencyDecisionProvider(candidate.page, false)
            let allRuntimesAllowAutomaticUnload = decision.allowsAutomaticUnload
            // Re-checked after the await: a page can be selected back onto the
            // screen while WebKit is answering for it.
            guard tabRuntimes[candidate.tabID]?.page === candidate.page,
                !runtimeStore.presentedTabIDs.contains(candidate.tabID),
                allRuntimesAllowAutomaticUnload
            else { continue }
            eligiblePages.append((candidate.tabID, candidate.page))
        }
        eligiblePages += nativeTabs.inactiveTabIDs(excluding: Array(runtimeStore.presentedTabIDs)).map { ($0, nil) }
        let releaseLimit = BrowserMemoryPressureReleasePolicy.releaseLimit(
            for: level,
            eligiblePageCount: eligiblePages.count,
            platform: .desktop
        )
        var releasedCount = 0
        for candidate in eligiblePages {
            guard !Task.isCancelled else { return }
            guard releasedCount < releaseLimit else { break }
            // Later decisions also await WebKit. An earlier candidate may have
            // become visible in any window or acquired a different runtime.
            guard !runtimeStore.presentedTabIDs.contains(candidate.tabID),
                tabRuntimes[candidate.tabID]?.page === candidate.page
            else { continue }
            evictPage(candidate.tabID)
            releasedCount += 1
        }
    }

    private func evictPage(_ tabID: TabID, preservingTabState: Bool = true) {
        nativeTabs.remove(tabID)
        runtimeStore.removePresentation(of: tabID)
        if preservingTabState {
            archiveTabState(for: tabID)
        }
        guard let runtime = tabRuntimes.removeValue(forKey: tabID) else { return }
        forgetBackgroundPageObservation(for: tabID)
        runtime.prepareForRelease()
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
        peekPageLeases.removeAll()
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

extension BrowserPagePool: BrowserTabCopying {
    func prepareTabCopy(from source: BrowserTab, to copy: inout BrowserTab, in space: BrowserSpace) {
        let state: Data?
        if let page = tabRuntimes[source.id]?.page, page.spaceID == space.id, page.profileID == space.profile.id {
            copy.url = page.displayURL ?? source.url
            copy.title = page.title.isEmpty ? source.title : page.title
            state = !page.wasOpenedAsPopup && page.url == copy.url ? page.interactionState : nil
        } else if let url = source.url {
            state = archivedInteractionState(
                for: source, spaceID: space.id, profileID: space.profile.id, expecting: url, consumePendingCopy: false)
        } else {
            state = nil
        }
        guard let state else { return }
        let assignment = BrowserTabRuntimeAssignment(tabID: copy.id, spaceID: space.id, profileID: space.profile.id)
        tabState.prepareCopy(state, url: copy.url, for: assignment)
    }
}

extension BrowserPagePool: BrowserTabLinkProviding {
    func linkURL(for tab: BrowserTab, in space: BrowserSpace) -> URL? {
        guard tab.isWebPage else { return nil }
        guard let page = tabRuntimes[tab.id]?.page,
            page.spaceID == space.id,
            page.profileID == space.profile.id
        else { return tab.url }
        return page.url
    }
}
