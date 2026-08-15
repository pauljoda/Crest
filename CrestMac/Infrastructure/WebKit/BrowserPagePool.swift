import AppKit
import Dispatch
import Foundation
import Observation
import WebKit
import os

@Observable
@MainActor
final class BrowserPagePool: BrowserSpaceDataDeleting, BrowserPageHosting {
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
    let permissionCenter: BrowserSitePermissionCenter
    let serverTrustOverrides = BrowserServerTrustOverrideStore()

    @ObservationIgnored private var pages: [TabID: BrowserPage] = [:]
    @ObservationIgnored private var inactiveSinceByTabID: [TabID: Date] = [:]
    @ObservationIgnored private var ephemeralDataStores: [UUID: WKWebsiteDataStore] = [:]
    @ObservationIgnored private let residencyDecisionProvider: ResidencyDecisionProvider
    @ObservationIgnored private var memoryPressureReleaseTask: Task<Void, Never>?
    @ObservationIgnored private let browsingMode: BrowserBrowsingMode
    @ObservationIgnored private let usesEphemeralWebsiteDataStores: Bool
    @ObservationIgnored private let chromeWebStoreProvider: BrowserChromeWebStoreProvider
    @ObservationIgnored private let mozillaAddonsProvider: BrowserMozillaAddonsProvider
    @ObservationIgnored private let dialogPresenter: BrowserDialogPresenter
    @ObservationIgnored private let popupTabHost: BrowserPopupTabHost
    @ObservationIgnored private let openNewTab: (URL) -> Void
    @ObservationIgnored private let openModifiedLink: (URL, SpaceID, Bool) -> Void
    @ObservationIgnored private let openPeek: (BrowserPeekRequest) -> Void
    @ObservationIgnored private let splitLinkHost: BrowserSplitLinkHost
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
    @ObservationIgnored private var spacesReleasingData: Set<SpaceID> = []
    @ObservationIgnored private var spacesDeletingData: Set<SpaceID> = []
    /// Where unloaded tabs leave their WebKit session state. Always nil for a
    /// private pool, so private browsing cannot write one even if an archive is
    /// handed in.
    @ObservationIgnored private let tabStateArchive: (any BrowserTabStateArchiving)?
    @ObservationIgnored private var lastPrunedTabIDsByProfileID: [UUID: Set<TabID>] = [:]

    init(
        monitorsMemoryPressure: Bool = false,
        browsingMode: BrowserBrowsingMode = .standard,
        usesEphemeralWebsiteDataStores: Bool =
            BrowserLaunchIsolationPolicy.requiresIsolation(.current),
        extensionControllerPool: BrowserExtensionControllerPool = BrowserExtensionControllerPool(),
        chromeWebStoreProvider: BrowserChromeWebStoreProvider =
            BrowserChromeWebStoreProvider(),
        mozillaAddonsProvider: BrowserMozillaAddonsProvider =
            BrowserMozillaAddonsProvider(),
        permissionCenter: BrowserSitePermissionCenter = BrowserSitePermissionCenter(),
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
        openModifiedLink: @escaping (URL, SpaceID, Bool) -> Void = { _, _, _ in },
        openPeek: @escaping (BrowserPeekRequest) -> Void = { _ in },
        splitLinkHost: BrowserSplitLinkHost = .unavailable,
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
        self.tabStateArchive =
            self.usesEphemeralWebsiteDataStores
            ? nil
            : tabStateArchive
        self.extensionControllerPool = extensionControllerPool
        self.chromeWebStoreProvider = chromeWebStoreProvider
        self.mozillaAddonsProvider = mozillaAddonsProvider
        self.permissionCenter = permissionCenter
        self.dialogPresenter = dialogPresenter
        self.popupTabHost = popupTabHost
        self.loadHTTPAuthenticationCredential = loadHTTPAuthenticationCredential
        self.saveHTTPAuthenticationCredential = saveHTTPAuthenticationCredential
        self.websiteDataStoreRemover = websiteDataStoreRemover
        self.contentRuleListProvider = contentRuleListProvider
        self.openNewTab = openNewTab
        self.openModifiedLink = openModifiedLink
        self.openPeek = openPeek
        self.splitLinkHost = splitLinkHost
        downloadCenter = BrowserDownloadCenter(
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
        guard let page = pages[tabID], page.spaceID == spaceID else {
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
        activePage?.canGoBack == true
    }

    var canGoForward: Bool {
        activePage?.canGoForward == true
    }

    var backHistory: [BrowserNavigationHistoryItem] {
        activePage?.backHistory ?? []
    }

    var forwardHistory: [BrowserNavigationHistoryItem] {
        activePage?.forwardHistory ?? []
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
        let interval = Self.lifecycleSignposter.beginInterval("Select Browser Page")
        defer {
            Self.lifecycleSignposter.endInterval("Select Browser Page", interval)
        }

        guard let tab, let space,
            !spacesReleasingData.contains(space.id),
            !spacesDeletingData.contains(space.id)
        else {
            deactivatePagePresentation(at: time)
            return
        }
        // Every member of the selected tab's split group is a live card, so
        // each one is built and started here. A card the person can see must
        // never wait for focus to load: lazy loading is for tabs off screen.
        let members = presentedMembers(for: tab, in: space)
        let memberPages = members.map { (tab: $0, page: page(for: $0, space: space)) }
        activate(tab.id, presenting: members.map(\.id), at: time)
        for member in memberPages {
            loadInitialURL(for: member.tab, into: member.page)
        }
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
        select(
            tab: session.selectedTab,
            space: session.selectedSpace,
            at: time
        )
        extensionControllerPool.reconcileExtensionState(in: session)
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
            inactiveSinceByTabID[tabID] = time
        }
        if let activeTabID, !presentedTabIDs.contains(activeTabID) {
            inactiveSinceByTabID[activeTabID] = time
        }
        presentedTabIDs = []
        activeTabID = nil
    }

    func restoreExtensions(in session: BrowserSession) async {
        guard !browsingMode.isPrivate else { return }
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
        onUserActivity: @escaping () -> Void = {}
    ) -> BrowserTransientPageLease? {
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard canHostTransientPage(matching: assignment) else { return nil }
        let lease = BrowserTransientPageLease(
            page: makePage(space: space),
            url: url,
            contentBlockingPolicy:
                space.browsingPreferences.contentBlockingPolicy,
            balancedContentRuleLists: balancedContentRuleLists ?? [],
            rebuild: { [weak self] in
                guard let self,
                    canHostTransientPage(matching: assignment)
                else { return nil }
                return makePage(space: space)
            },
            userActivity: onUserActivity
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

    /// Adopts the web view WebKit pre-made for a popup as a new selected tab in
    /// the opener's Space.
    ///
    /// Declines — leaving the coordinator to route the destination into an
    /// ordinary tab — when the opener is not a resident page of this pool. That
    /// covers Peek and Quick Window openers, whose pages belong to transient
    /// leases with no tab of their own, so a popup from one cannot inherit a
    /// place in the tab list.
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

        let page = makePage(space: registration.space, adoptedConfiguration: configuration)
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

    func goBack() {
        activePage?.goBack()
    }

    func goForward() {
        activePage?.goForward()
    }

    func goBack(to item: BrowserNavigationHistoryItem) {
        activePage?.goBack(toDepth: item.depth)
    }

    func goForward(to item: BrowserNavigationHistoryItem) {
        activePage?.goForward(toDepth: item.depth)
    }

    func unloadPage(for tabID: TabID) {
        // Archived before the page is torn down: a tab closed by hand can be
        // reopened, and a tab unloaded by hand is expected to come back where it
        // was left.
        archiveTabState(for: tabID)
        guard let page = pages.removeValue(forKey: tabID) else { return }
        page.prepareForSpaceDeletion()
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

    /// Releases only the resident WebKit pages owned by one Space. Ordinary
    /// Space selection never calls this; it is the residency half of a protected
    /// Space returning to its locked state, so its content cannot stay resident.
    ///
    /// Nothing is archived on the way out, unlike an idle or manual unload: a locked Space is
    /// meant to leave nothing behind, and `relockProtectedSpace(_:)` is the
    /// entry point that also clears what earlier unloads already wrote.
    func unloadPages(in spaceID: SpaceID) {
        let tabIDs = Set(
            pages.compactMap { tabID, page in
                page.spaceID == spaceID ? tabID : nil
            }
        )
        _ = releasePages(for: tabIDs)
        _ = releaseTransientPages(in: spaceID)
    }

    /// Takes a protected Space back to its locked state: releases its resident
    /// pages, then purges every tab state archived under its profile.
    ///
    /// Unloading alone only settles what is in memory *now*. Unloads taken while
    /// the Space was unlocked — the idle timeout or a hand unload — each left an
    /// `interactionState` blob on disk, and those
    /// blobs carry scroll offsets, form values, and the full back/forward list
    /// of pages the lock is supposed to put away. The session JSON keeps URLs
    /// either way, so this is not about hiding that the Space was used; it is
    /// about not leaving page-level residue readable while the Space is locked,
    /// which costs nothing but a reload after the next unlock.
    ///
    /// The purge is enqueued after the release, and the archive's writes are
    /// serialized, so a state archived a moment ago cannot outrun it. An
    /// unlocked Space is left entirely alone — including its archive — so this
    /// is safe to call for any Space the lock sweep hands over.
    func relockProtectedSpace(_ space: BrowserSpace) {
        unloadPages(in: space.id)
        guard space.accessPolicy.requiresAuthentication else { return }
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
        if let existingPage = pages[tab.id] {
            if existingPage.spaceID == space.id,
                existingPage.profileID == space.profile.id
            {
                existingPage.setCredentialAccessEnabled(
                    space.credentialPreferences.isEnabled
                )
                existingPage.updateNavigationContext(
                    tab: tab,
                    automaticallyOpensPeek: BrowserLinkPreferenceStore.shared
                        .preferences.automaticallyOpensPeek
                )
                return existingPage
            }
            // The tab moved to another Space, so the state archived under its old
            // profile describes a runtime it no longer belongs to.
            tabStateArchive?.removeState(
                profileID: existingPage.profileID,
                tabID: tab.id
            )
            existingPage.prepareForSpaceDeletion()
            pages.removeValue(forKey: tab.id)
            inactiveSinceByTabID[tab.id] = nil
        }
        let page = makePage(
            space: space,
            extensionConfiguration: tab.url.flatMap {
                extensionControllerPool.webViewConfiguration(
                    for: $0,
                    in: space.id
                )
            }
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

    /// Builds a page for `space`. Popup and extension-page configurations are
    /// both supplied by WebKit and must be used exactly as handed over.
    private func makePage(
        space: BrowserSpace,
        adoptedConfiguration: WKWebViewConfiguration? = nil,
        extensionConfiguration: WKWebViewConfiguration? = nil
    ) -> BrowserPage {
        let interval = Self.lifecycleSignposter.beginInterval("Create Browser Page")
        defer {
            Self.lifecycleSignposter.endInterval("Create Browser Page", interval)
        }

        let contentRuleLists = contentRuleLists(for: space)
        let page = BrowserPage(
            configuration: adoptedConfiguration
                ?? extensionConfiguration
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
            serverTrustOverrides: serverTrustOverrides,
            spaceID: space.id,
            profileID: space.profile.id,
            spaceName: space.name,
            contentRuleLists: contentRuleLists,
            ownsUserContentController: adoptedConfiguration == nil
                && extensionConfiguration == nil,
            allowsCredentialAccess: !browsingMode.isPrivate,
            isCredentialAccessEnabled:
                space.credentialPreferences.isEnabled,
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
            openModifiedLink: openModifiedLink,
            openPeek: openPeek,
            splitLinkHost: splitLinkHost
        )
        page.host = self
        return page
    }

    private func tabID(for page: BrowserPage) -> TabID? {
        pages.first { $0.value === page }?.key
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

    @discardableResult
    private func releasePages(
        for tabIDs: Set<TabID>
    ) -> [BrowserSpaceDataReleaseProbe] {
        var releasedAnyPage = false
        var probes: [BrowserSpaceDataReleaseProbe] = []
        for tabID in tabIDs {
            if let page = pages.removeValue(forKey: tabID) {
                probes.append(BrowserSpaceDataReleaseProbe(page))
                page.prepareForSpaceDeletion()
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
            let decision = await residencyDecisionProvider(candidate.page, false)
            // Re-checked after the await: a page can be selected back onto the
            // screen while WebKit is answering for it.
            guard pages[candidate.tabID] === candidate.page,
                !presentedTabIDs.contains(candidate.tabID),
                decision.allowsAutomaticUnload
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
        page.prepareForSpaceDeletion()
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
