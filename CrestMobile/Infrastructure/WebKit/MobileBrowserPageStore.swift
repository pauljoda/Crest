import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

@Observable
@MainActor
final class MobileBrowserPageStore:
    BrowserSpaceDataDeleting,
    MobileBrowserPageHosting,
    BrowserDefaultPageZoomObserving
{
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
        @MainActor (MobileBrowserPage, Bool) async -> BrowserPageResidencyDecision

    typealias ModifiedLinkOpener =
        @MainActor (URL, SpaceID, Bool) -> BrowserModifiedLinkRegistration?

    @ObservationIgnored private let backgroundPageDidUpdate: (BrowserBackgroundPageUpdate) -> Void
    @ObservationIgnored private var backgroundPageSnapshots: [TabID: BrowserBackgroundPageSnapshot] = [:]
    @ObservationIgnored private var backgroundPageAssignments: [TabID: BrowserSpaceRuntimeAssignment] = [:]

    /// The focused card: the one page the toolbar, find bar, navigation
    /// controls, and every lifecycle observer speak for. Split View adds cards
    /// beside it without adding a second focus.
    private(set) var activePage: MobileBrowserPage? {
        willSet { if activePage !== newValue { activePage?.translation.suspend() } }
    }

    /// Every card the content area is presenting, in session member order.
    ///
    /// Derived from `BrowserSpace.presentedSplitMembers(for:)` — the same source
    /// the sidebar folds its group row from, so the two can never disagree about
    /// who is on screen. A tab outside a renderable split presents alone, which
    /// is one element rather than a special case, and the active page is always
    /// a member while anything is presented.
    ///
    /// Deliberately observable: a carousel cell and an iPad column both read it
    /// through `residentPage(matching:)` and have to re-render when membership
    /// changes.
    private(set) var presentedTabIDs: [TabID] = []
    let nativeTabs = BrowserNativeTabStore()
    private(set) var residencyRevision = 0
    private(set) var urlCopyFeedbackRevision = 0
    private(set) var pageZoomFeedbackLabel = "100%"
    private(set) var pageZoomFeedbackRevision = 0
    var contentBlockingErrorDescription: String? { contentBlocking.errorDescription }
    let downloadCenter: BrowserDownloadCenter
    let downloadRiskConfirmation: MobileDownloadRiskConfirmationCoordinator
    let permissionCenter: BrowserSitePermissionCenter
    let serverTrustOverrides = BrowserServerTrustOverrideStore()

    @ObservationIgnored private var pagesByTabID: [TabID: MobileBrowserPage] = [:]
    @ObservationIgnored private var inactiveSinceByTabID: [TabID: Date] = [:]
    @ObservationIgnored private var ephemeralDataStores: [UUID: WKWebsiteDataStore] = [:]
    @ObservationIgnored private let popupTabHost: BrowserPopupTabHost
    @ObservationIgnored private let mediaSessionStore: BrowserMediaSessionStore?
    @ObservationIgnored let linkDestinationHost: BrowserLinkDestinationHost
    @ObservationIgnored private let openNewTab: (URL) -> Void
    @ObservationIgnored private let openModifiedLink: ModifiedLinkOpener
    @ObservationIgnored private let openPeek: (BrowserPeekRequest) -> Void
    @ObservationIgnored private let residencyDecisionProvider: ResidencyDecisionProvider
    @ObservationIgnored private var memoryPressureReleaseTask: Task<Void, Never>?
    @ObservationIgnored private let browsingMode: BrowserBrowsingMode
    @ObservationIgnored private let usesEphemeralWebsiteDataStores: Bool
    @ObservationIgnored private let pageZoomPreferences: BrowserDefaultPageZoomStore
    @ObservationIgnored private let loadHTTPAuthenticationCredential: HTTPAuthenticationCredentialLoader
    @ObservationIgnored private let saveHTTPAuthenticationCredential: HTTPAuthenticationCredentialSaver
    @ObservationIgnored private let profileRemover: any BrowserEngineProfileRemoving
    @ObservationIgnored private let contentBlocking: BrowserContentBlockingController
    @ObservationIgnored private var memoryPressureSource: (any DispatchSourceMemoryPressure)?
    @ObservationIgnored private var memoryPressureCoalescer = BrowserMemoryPressureCoalescer()
    @ObservationIgnored private var peekPageLeases:
        [UUID: (request: BrowserPeekRequest, lease: MobileBrowserTransientPageLease)] = [:]
    @ObservationIgnored private var transientLeases: [UUID: WeakBrowserTransientPageLease] = [:]
    @ObservationIgnored private var spacesReleasingData: Set<SpaceID> = []
    @ObservationIgnored private var spacesDeletingData: Set<SpaceID> = []
    /// Where unloaded tabs leave their WebKit session state. Its archive is nil
    /// for a private store, even if an archive is handed in.
    @ObservationIgnored private let tabState: BrowserTabStateCoordinator

    init(
        monitorsMemoryPressure: Bool = false,
        browsingMode: BrowserBrowsingMode = .standard,
        usesEphemeralWebsiteDataStores: Bool =
            BrowserLaunchEnvironment.current.requiresIsolation,
        pageZoomPreferences: BrowserDefaultPageZoomStore = .shared,
        permissionCenter: BrowserSitePermissionCenter = BrowserSitePermissionCenter(),
        mediaSessionStore: BrowserMediaSessionStore? = nil,
        downloads: MobileBrowserDownloads? = nil,
        loadHTTPAuthenticationCredential:
            @escaping HTTPAuthenticationCredentialLoader = { _, _ in nil },
        saveHTTPAuthenticationCredential:
            @escaping HTTPAuthenticationCredentialSaver = { _, _ in },
        profileRemover:
            any BrowserEngineProfileRemoving = WebKitBrowserWebsiteDataStoreRemover(),
        contentRuleListProvider: (any BrowserContentRuleListProviding)? = nil,
        tabStateArchive: (any BrowserTabStateArchiving)? = nil,
        popupTabHost: BrowserPopupTabHost = .unavailable,
        linkDestinationHost: BrowserLinkDestinationHost = .unavailable,
        openNewTab: @escaping (URL) -> Void = { _ in },
        openModifiedLink: @escaping ModifiedLinkOpener = { _, _, _ in nil },
        backgroundPageDidUpdate: @escaping (BrowserBackgroundPageUpdate) -> Void = { _ in },
        openPeek: @escaping (BrowserPeekRequest) -> Void = { _ in },
        residencyDecisionProvider: @escaping ResidencyDecisionProvider = {
            page,
            isSelected in
            await page.residencyDecision(isSelected: isSelected)
        }
    ) {
        self.residencyDecisionProvider = residencyDecisionProvider
        self.browsingMode = browsingMode
        self.usesEphemeralWebsiteDataStores =
            usesEphemeralWebsiteDataStores || browsingMode.isPrivate
        self.pageZoomPreferences = pageZoomPreferences
        tabState = BrowserTabStateCoordinator(
            archive: self.usesEphemeralWebsiteDataStores ? nil : tabStateArchive
        )
        self.popupTabHost = popupTabHost
        self.mediaSessionStore = browsingMode.isPrivate ? nil : mediaSessionStore
        self.permissionCenter = permissionCenter
        self.loadHTTPAuthenticationCredential = loadHTTPAuthenticationCredential
        self.saveHTTPAuthenticationCredential = saveHTTPAuthenticationCredential
        self.profileRemover = profileRemover
        self.linkDestinationHost = linkDestinationHost
        self.openNewTab = openNewTab
        self.openModifiedLink = openModifiedLink
        self.backgroundPageDidUpdate = backgroundPageDidUpdate
        self.openPeek = openPeek
        // Windows share their browsing mode's downloads; a store made on its
        // own, such as a preview's, gets a memory-only core of its own.
        let downloads =
            downloads
            ?? MobileBrowserDownloads(
                core: CrestCore(),
                browsingMode: browsingMode,
                permissionCenter: permissionCenter,
                loadCredential: loadHTTPAuthenticationCredential,
                saveCredential: saveHTTPAuthenticationCredential
            )
        downloadRiskConfirmation = downloads.riskConfirmation
        downloadCenter = downloads.center
        contentBlocking = BrowserContentBlockingController(
            provider: contentRuleListProvider ?? BrowserContentRuleListProvider.forLaunch(core: downloads.center.core))
        if monitorsMemoryPressure {
            installMemoryPressureSource()
        }
        pageZoomPreferences.register(self)
    }

    deinit {
        memoryPressureReleaseTask?.cancel()
        memoryPressureSource?.cancel()
    }

    var canGoBack: Bool { activePage?.canGoBack == true }
    var canGoForward: Bool { activePage?.canGoForward == true }
    var backHistory: [BrowserNavigationHistoryItem] { activePage?.backHistory ?? [] }
    var forwardHistory: [BrowserNavigationHistoryItem] { activePage?.forwardHistory ?? [] }
    var activeURL: URL? { activePage?.url }
    var pageZoomLabel: String {
        BrowserPageZoomPolicy.percentageLabel(for: activePage?.pageZoom ?? 1)
    }
    var readerModeState: BrowserReaderModeState {
        activePage?.readerModeState ?? .unavailable
    }
    var readerModeActionTitle: LocalizedStringResource {
        readerModeState.isActive ? "Hide Reader" : "Show Reader"
    }
    var preferredContentModeActionTitle: LocalizedStringResource {
        activePage?.isRequestingDesktopSite == true
            ? "Request Mobile Website"
            : "Request Desktop Website"
    }
    var residentPageCount: Int { pagesByTabID.count }

    var retainedTransientPageCount: Int {
        pruneTransientLeases()
        return transientLeases.values.compactMap(\.value).filter { $0.page != nil }.count
    }

    func prepareContentBlocking() async {
        await contentBlocking.prepare()
    }

    /// Reloads presented pages only when their Space's protection level changes.
    func reconcileContentBlocking(in session: BrowserSession) async {
        let update = await contentBlocking.reconcile(in: session)
        for (tabID, page) in pagesByTabID {
            let isPresentedPage = presentedTabIDs.contains(tabID)
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

    /// Presents what the window selects. `session` pairs the core's data with
    /// that window's own selection.
    func select(session: BrowserPresentedSession) {
        select(session: session, at: .now)
    }

    func select(session: BrowserPresentedSession, at time: Date) {
        if !prepareSelectedPage(in: session, at: time) {
            deactivatePagePresentation(at: time)
        }
        reconcileCredentialAccess(in: session.session)
    }

    func selectAndLoad(
        _ url: URL,
        in session: BrowserPresentedSession,
        at time: Date = .now
    ) {
        if prepareSelectedPage(
            in: session,
            at: time,
            loadsInitialURL: false
        ) {
            activePage?.load(url)
        } else {
            deactivatePagePresentation(at: time)
        }
        reconcileCredentialAccess(in: session.session)
    }

    func loadOpenedLink(_ registration: BrowserModifiedLinkRegistration, request: URLRequest, selecting: Bool) {
        let space = registration.space
        guard registration.tab.nativeContent == nil, !spacesReleasingData.contains(space.id),
            !spacesDeletingData.contains(space.id)
        else { return }
        let page = makeResidentPage(for: registration.tab, in: space, loadsInitialURL: false)
        pagesByTabID[registration.tab.id] = page
        residencyRevision &+= 1
        observeBackgroundPage(page, in: space)
        page.load(request)
        if selecting { select(session: registration.session) }
    }

    private func observeBackgroundPage(_ page: MobileBrowserPage, in space: BrowserSpace) {
        backgroundPageAssignments[page.tabID] = BrowserSpaceRuntimeAssignment(space: space)
        backgroundPageSnapshots[page.tabID] = BrowserBackgroundPageSnapshot(page: page)
        trackBackgroundPageChanges(page)
    }

    private func trackBackgroundPageChanges(_ page: MobileBrowserPage) {
        withObservationTracking {
            _ = BrowserBackgroundPageSnapshot(page: page)
        } onChange: { [weak self, weak page] in
            Task { @MainActor in
                guard let self, let page else { return }
                self.backgroundPageDidChange(page)
            }
        }
    }

    private func backgroundPageDidChange(_ page: MobileBrowserPage) {
        let tabID = page.tabID
        guard pagesByTabID[tabID] === page,
            let assignment = backgroundPageAssignments[tabID]
        else { return }
        let previous = backgroundPageSnapshots[tabID]
        let current = BrowserBackgroundPageSnapshot(page: page)
        backgroundPageSnapshots[tabID] = current
        trackBackgroundPageChanges(page)
        if current.completedNavigationCount > 0 || current.hasNavigationFailure
            || (previous?.isLoading == true && !current.isLoading)
        {
            stampPreparedPageIfNeeded(tabID, at: .now)
        }
        guard previous != current, !presentedTabIDs.contains(tabID) else { return }
        let completedURL =
            current.completedNavigationCount > (previous?.completedNavigationCount ?? 0)
            ? page.url : nil
        backgroundPageDidUpdate(
            BrowserBackgroundPageUpdate(
                tabID: tabID, assignment: assignment, url: current.url,
                title: current.title, faviconData: current.faviconData,
                iconAccent: current.iconAccent, estimatedProgress: current.estimatedProgress,
                isLoading: current.isLoading, readerModeState: current.readerModeState,
                completedNavigationURL: completedURL, processTerminationCount: 0
            ))
    }

    private func prepareSelectedPage(
        in session: BrowserPresentedSession,
        at time: Date,
        loadsInitialURL: Bool = true
    ) -> Bool {
        guard let space = session.selectedSpace,
            let tab = session.selectedTab,
            !spacesReleasingData.contains(space.id),
            !spacesDeletingData.contains(space.id)
        else {
            return false
        }
        // Unlike macOS, only the focused member is built here. The carousel
        // materializes its cells lazily and each one calls
        // `prepareResidentPage(for:in:)` as it approaches, which is what keeps a
        // four-member group to focused ±1 live web views on a phone.
        let presented = presentedMemberIDs(for: tab, in: space)
        if tab.nativeContent != nil {
            nativeTabs.load(tab: tab, space: space, at: time)
            deactivatePagePresentation(at: time)
            presentedTabIDs = presented
            return true
        }
        if let existing = pagesByTabID[tab.id],
            existing.spaceID == space.id,
            existing.profileID == space.profile.id
        {
            existing.setCredentialAccessEnabled(
                space.credentialPreferences.isEnabled
            )
            existing.updateNavigationContext(
                tab: tab,
                automaticallyOpensPeek: BrowserLinkPreferenceStore.shared
                    .preferences.automaticallyOpensPeek
            )
            activate(existing, presenting: presented, at: time)
            return true
        }

        if let mismatched = pagesByTabID.removeValue(forKey: tab.id) {
            // The tab moved to another Space, so the state archived under its old
            // profile describes a runtime it no longer belongs to.
            tabState.removeState(
                profileID: mismatched.profileID,
                tabID: tab.id
            )
            mismatched.prepareForSpaceDeletion()
            inactiveSinceByTabID[tab.id] = nil
        }

        let page = makeResidentPage(
            for: tab,
            in: space,
            loadsInitialURL: loadsInitialURL
        )
        pagesByTabID[tab.id] = page
        residencyRevision &+= 1
        activate(page, presenting: presented, at: time)
        return true
    }

    /// The cards `tab` brings on screen, in session member order.
    ///
    /// A tab the Space does not carry at all presents alone rather than not at
    /// all: selection can hand over a value the store has already moved past.
    private func presentedMemberIDs(
        for tab: BrowserTab,
        in space: BrowserSpace
    ) -> [TabID] {
        let members = space.presentedSplitMembers(for: tab.id).map(\.id)
        return members.contains(tab.id) ? members : [tab.id]
    }

    /// Builds a resident page for a presented card that is not the focused one.
    ///
    /// Same guards as the selected-page path minus the activation: the card is
    /// on screen, so its page must start loading immediately, but focus stays
    /// where the session put it. Answers the page a card can bind, or `nil` when
    /// the tab is not a live member of the selected Space right now.
    @discardableResult
    func prepareResidentPage(
        for tabID: TabID,
        in session: BrowserPresentedSession,
        at time: Date = .now
    ) -> MobileBrowserPage? {
        guard let space = session.selectedSpace,
            let tab = space.tabs.first(where: { $0.id == tabID }),
            !spacesReleasingData.contains(space.id),
            !spacesDeletingData.contains(space.id)
        else { return nil }

        if tab.nativeContent != nil {
            nativeTabs.load(tab: tab, space: space, at: time)
            return nil
        }
        if let existing = pagesByTabID[tabID],
            existing.spaceID == space.id,
            existing.profileID == space.profile.id
        {
            existing.setCredentialAccessEnabled(
                space.credentialPreferences.isEnabled
            )
            existing.updateNavigationContext(
                tab: tab,
                automaticallyOpensPeek: BrowserLinkPreferenceStore.shared
                    .preferences.automaticallyOpensPeek
            )
            stampPreparedPageIfNeeded(tabID, at: time)
            return existing
        }

        if let mismatched = pagesByTabID.removeValue(forKey: tabID) {
            tabState.removeState(
                profileID: mismatched.profileID,
                tabID: tabID
            )
            mismatched.prepareForSpaceDeletion()
            inactiveSinceByTabID[tabID] = nil
        }

        let page = makeResidentPage(for: tab, in: space)
        pagesByTabID[tabID] = page
        stampPreparedPageIfNeeded(tabID, at: time)
        residencyRevision &+= 1
        return page
    }

    /// Puts a prepared card into the idle ledger.
    ///
    /// Eviction candidates come from `inactiveSinceByTabID` and nowhere else, so
    /// a page built for a card and never activated would be permanently
    /// invisible to memory pressure — it would outlive every page the person
    /// actually used. An existing stamp is left alone: it already records when
    /// this page last had attention, and refreshing it would make an old card
    /// look new every time the carousel re-materialized its cell.
    private func stampPreparedPageIfNeeded(_ tabID: TabID, at time: Date) {
        guard activePage?.tabID != tabID,
            inactiveSinceByTabID[tabID] == nil
        else { return }
        inactiveSinceByTabID[tabID] = time
    }

    /// The resident page of a presented card, once its Space and profile are
    /// confirmed to be the ones the caller is drawing.
    ///
    /// A card binds a page it did not select, so the drift the selected-page port
    /// guards against is a live risk here too: a Space switch or a profile
    /// rebuild can leave a cell holding a stale assignment for one frame, and
    /// binding a page across that boundary is exactly the isolation failure
    /// per-Space browsing exists to prevent.
    ///
    /// Membership is checked rather than residency alone: a background tab can
    /// keep a resident page for as long as memory allows, and handing one to a
    /// card would put a second host on a web view that already has one.
    func residentPage(
        matching assignment: BrowserTabRuntimeAssignment
    ) -> MobileBrowserPage? {
        _ = residencyRevision
        guard presentedTabIDs.contains(assignment.tabID),
            let page = pagesByTabID[assignment.tabID],
            page.spaceID == assignment.spaceID,
            page.profileID == assignment.profileID
        else { return nil }
        return page
    }

    /// Removes every rendered page from presentation without evicting their
    /// isolated WebKit runtimes. Selecting that tab again can reuse the resident
    /// page, but no previous Space can remain visible underneath the tab viewer
    /// or a private-Space lock transition.
    ///
    /// All of it goes at once, not just the focused card: a Space locking with a
    /// split open has to take every card away, and half a split left on screen
    /// would be the privacy failure the gate exists to prevent.
    func deactivatePagePresentation(at time: Date = .now) {
        guard activePage != nil || !presentedTabIDs.isEmpty else { return }
        for tabID in presentedTabIDs where pagesByTabID[tabID] != nil {
            stampPreparedPageIfNeeded(tabID, at: time)
        }
        if let activePage {
            inactiveSinceByTabID[activePage.tabID] = time
        }
        presentedTabIDs = []
        self.activePage = nil
    }

    func reconcile(validTabIDs: Set<TabID>) {
        nativeTabs.reconcile(validTabIDs: validTabIDs)
        tabState.retainCopies(for: validTabIDs)
        let removedTabIDs = Set(pagesByTabID.keys).subtracting(validTabIDs)
        for tabID in removedTabIDs {
            // These tabs are gone from the tab list rather than unloaded after
            // idling, so their state is not worth writing out here. Whether it
            // is worth keeping is settled by the session sweep, which can tell an
            // archived tab from a deleted one.
            evictPage(tabID, preservingTabState: false)
        }
        if let activePage, !validTabIDs.contains(activePage.tabID) {
            self.activePage = nil
        }
        // A card whose tab is gone must stop being a card in the same pass, or
        // the carousel would keep a cell for a member the session no longer has.
        if presentedTabIDs.contains(where: { !validTabIDs.contains($0) }) {
            presentedTabIDs = presentedTabIDs.filter { validTabIDs.contains($0) }
        }
    }

    func reconcile(session: BrowserSession) {
        nativeTabs.reconcile(session: session)
        let reconciliation = BrowserPageReconciliation(
            session: session,
            residentPages: pagesByTabID.lazy.map { ($0.key, $0.value) }
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

    /// Brings the download center, every resident page, and every transient lease
    /// in line with each Space's "save passwords" preference.
    ///
    /// The preference has to reach all three: HTTP authentication collects
    /// credentials outside any page, a background tab can be the one holding a
    /// pending save offer, and a Peek runs a page with no tab of its own.
    func reconcileCredentialAccess(in session: BrowserSession) {
        let enabledBySpaceID = Dictionary(
            uniqueKeysWithValues: session.spaces.map {
                ($0.id, $0.credentialPreferences.isEnabled)
            }
        )
        for (spaceID, isEnabled) in enabledBySpaceID {
            downloadCenter.setCredentialAccessEnabled(isEnabled, in: spaceID)
        }
        for page in pagesByTabID.values {
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

    func reconcileTabIcons(in session: BrowserSession) {
        let tabsByID = Dictionary(
            uniqueKeysWithValues: session.spaces.flatMap { space in
                space.tabs.map { ($0.id, $0) }
            }
        )
        for (tabID, page) in pagesByTabID {
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
        try await profileRemover.removeProfile(space.profile, ephemeral: usesEphemeralWebsiteDataStores)
        permissionCenter.reset(spaceID: space.id)
    }

    func releaseWindowRuntime(for space: BrowserSpace) async {
        nativeTabs.remove(in: space.id)
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
        nativeTabs.reconcile(validTabIDs: [])
        for page in pagesByTabID.values {
            page.prepareForSpaceDeletion()
        }
        pagesByTabID.removeAll()
        backgroundPageSnapshots.removeAll()
        backgroundPageAssignments.removeAll()
        residencyRevision &+= 1
        inactiveSinceByTabID.removeAll()
        memoryPressureReleaseTask?.cancel()
        memoryPressureReleaseTask = nil
        activePage = nil
        presentedTabIDs = []
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

    func styleVisitedLinks(in space: BrowserSpace) async {
        await activePage?.styleVisitedLinks(history: space.history)
    }

    func makePeekPageLease(
        request: BrowserPeekRequest,
        in space: BrowserSpace,
        onDownloadOnlyNavigation: @escaping () -> Void
    ) -> MobileBrowserTransientPageLease? {
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
            engineNavigation: request.engineNavigation,
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
        engineNavigation: BrowserEngineNavigation? = nil,
        onUserActivity: @escaping () -> Void = {},
        onDownloadOnlyNavigation: (() -> Void)? = nil
    ) -> MobileBrowserTransientPageLease? {
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        guard canHostTransientPage(matching: assignment) else { return nil }
        let transientTab = BrowserTab(
            title: url.host() ?? url.absoluteString,
            url: url,
            placement: .current
        )
        let initialPage = makeTransientPage(
            tab: transientTab,
            in: space
        )
        // Only the first page replays the staged request; a rebuilt page
        // after memory pressure reloads its last URL like any other.
        if let engineNavigation,
            !initialPage.pageEngine.stageNavigation(engineNavigation, expecting: url) {
            initialPage.prepareForSpaceDeletion()
            return nil
        }
        initialPage.opensModifiedLinksInForeground = opensModifiedLinksInForeground
        let rebuild: () -> MobileBrowserPage? = { [weak self] in
            guard let self,
                canHostTransientPage(matching: assignment)
            else { return nil }
            let page = makeTransientPage(tab: transientTab, in: space)
            page.opensModifiedLinksInForeground = opensModifiedLinksInForeground
            return page
        }
        let lease = MobileBrowserTransientPageLease(
            page: initialPage,
            url: url,
            contentBlockingPolicy:
                space.browsingPreferences.contentBlockingPolicy,
            balancedContentRuleLists: contentBlocking.balancedRuleLists ?? [],
            rebuild: rebuild,
            userActivity: onUserActivity,
            onDownloadOnlyNavigation: onDownloadOnlyNavigation
        )
        transientLeases[lease.id] = WeakBrowserTransientPageLease(lease)
        return lease
    }

    private func makeTransientPage(
        tab: BrowserTab,
        in space: BrowserSpace
    ) -> MobileBrowserPage {
        let page = MobileBrowserPage(
            tab: tab,
            space: space,
            downloadCenter: downloadCenter,
            permissionCenter: permissionCenter,
            serverTrustOverrides: serverTrustOverrides,
            websiteDataStore: websiteDataStore(for: space.profile),
            contentRuleLists: contentRuleLists(for: space),
            allowsCredentialAccess: !browsingMode.isPrivate,
            isCredentialAccessEnabled: space.credentialPreferences.isEnabled,
            defaultPageZoom: pageZoomPreferences.defaultZoom,
            loadsInitialURL: false,
            loadHTTPAuthenticationCredential: { [loadHTTPAuthenticationCredential] protectionSpace in
                try await loadHTTPAuthenticationCredential(protectionSpace, space.id)
            },
            saveHTTPAuthenticationCredential: { [saveHTTPAuthenticationCredential] request in
                try await saveHTTPAuthenticationCredential(request, space.id)
            },
            linkDestinationHost: linkDestinationHost,
            openNewTab: openNewTab,
            openModifiedLink: openModifiedLink,
            openPeek: openPeek
        )
        page.host = self
        return page
    }

    @discardableResult
    func adoptTransientPage(
        _ lease: MobileBrowserTransientPageLease,
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
            page.profileID == assignment.profileID,
            let tab = space.tabs.first(where: { $0.id == tabID })
        else { return false }
        guard lease.relinquishPage() === page else { return false }
        page.opensModifiedLinksInForeground = false
        transientLeases.removeValue(forKey: lease.id)
        page.adopt(tabID: tabID, tab: tab)
        pagesByTabID[tabID] = page
        residencyRevision &+= 1
        activate(page, at: .now)
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
    /// ordinary tab — when the opener is not a resident page of this store. That
    /// covers Peek openers, whose pages belong to transient leases with no tab of
    /// their own, so a popup from one cannot inherit a place in the tab list.
    ///
    /// Per-Space isolation needs no work here: WebKit derives the popup's
    /// configuration from the opener's, so it already carries the opener's
    /// `websiteDataStore`. The Space lookup only
    /// confirms the tab landed in the opener's own profile.
    func adoptPopupWebView(
        configuration: WKWebViewConfiguration,
        requestedURL: URL?,
        opener: MobileBrowserPage,
        selecting: Bool = true
    ) -> WKWebView? {
        guard tabID(for: opener) != nil,
            !spacesReleasingData.contains(opener.spaceID),
            !spacesDeletingData.contains(opener.spaceID),
            let registration = popupTabHost.openTab(requestedURL, opener.spaceID, selecting),
            registration.space.id == opener.spaceID,
            registration.space.profile.id == opener.profileID
        else { return nil }

        let page = makeResidentPage(
            for: registration.tab,
            in: registration.space,
            adoptedConfiguration: configuration
        )
        page.markOpenedAsPopup()
        pagesByTabID[registration.tab.id] = page
        residencyRevision &+= 1
        if selecting {
            activate(page, at: .now)
        } else {
            observeBackgroundPage(page, in: registration.space)
        }
        return page.webView
    }

    /// Honors `window.close()` by closing the popup's tab through the same store
    /// path the tab list's close control uses. The page itself is released after
    /// the WebKit callback unwinds, because tearing a web view down inside its
    /// own delegate callback is not safe.
    func closeWebContentInitiatedPage(_ page: MobileBrowserPage) {
        guard page.wasOpenedAsPopup, let tabID = tabID(for: page) else { return }
        popupTabHost.closeTab(tabID, page.spaceID)
        Task { @MainActor [weak self] in
            self?.unloadPage(for: tabID)
        }
    }

    func discardDownloadOnlyPage(_ page: MobileBrowserPage) {
        if let entry = transientLeases.first(where: { $0.value.value?.page === page }),
            let lease = entry.value.value,
            lease.discardForDownloadOnlyNavigation()
        {
            transientLeases.removeValue(forKey: entry.key)
            return
        }
        closeWebContentInitiatedPage(page)
    }

    func routeGeolocationMessage(_ message: WKScriptMessage) {
        guard let sourceWebView = message.webView,
            let page = pagesByTabID.values.first(where: {
                $0.webView === sourceWebView
            })
        else { return }
        page.receiveGeolocationMessage(message)
    }

    func routeBlockedPopupMessage(_ message: WKScriptMessage) {
        guard let sourceWebView = message.webView,
            let page = pagesByTabID.values.first(where: {
                $0.webView === sourceWebView
            })
        else { return }
        page.receiveBlockedPopupMessage(message)
    }

    func routeMediaSessionMessage(_ message: WKScriptMessage) {
        guard let sourceWebView = message.webView,
            let page = pagesByTabID.values.first(where: {
                $0.webView === sourceWebView
            })
        else { return }
        page.receiveMediaSessionMessage(message)
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

    /// Explicit durable close differs from residency eviction only when the
    /// person chose to return to the saved URL on the next open.
    func closeDurablePage(_ assignment: BrowserTabRuntimeAssignment, discardState: Bool) -> Bool {
        guard !nativeTabs.tabIDs.contains(assignment.tabID) || nativeTabs.contains(assignment) else { return false }
        guard
            pagesByTabID[assignment.tabID].map({
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
            presentedTabIDs.removeAll { $0 == tabID }
        }
        forgetBackgroundPageObservation(for: tabID)
        // Archived before the page is torn down: a tab closed by hand can be
        // reopened, and a tab unloaded by hand is expected to come back where it
        // was left.
        if preservingTabState { archiveTabState(for: tabID) }
        guard let page = pagesByTabID.removeValue(forKey: tabID) else { return }
        page.prepareForSpaceDeletion()
        inactiveSinceByTabID[tabID] = nil
        if activePage?.tabID == tabID { activePage = nil }
        // A hand unload is a request to put the page away, so the card goes with
        // it. Memory-pressure eviction deliberately does not do this: that card
        // is still on screen and re-materializes as an unloaded placeholder.
        presentedTabIDs.removeAll { $0 == tabID }
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
        guard let page = pagesByTabID[tabID],
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
            pagesByTabID.compactMap { tabID, page in
                page.spaceID == spaceID ? tabID : nil
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
        if activePage?.spaceID == space.id
            || presentedTabIDs.contains(where: { pagesByTabID[$0]?.spaceID == space.id })
        {
            deactivatePagePresentation()
        }
        tabState.removeStates(profileID: space.profile.id)
    }

    func reloadOrStop() {
        activePage?.reloadOrStop()
    }

    func reload() {
        activePage?.reload()
    }

    func stopLoading() {
        activePage?.stopLoading()
    }

    func reloadFromOrigin() {
        activePage?.performReload(.fromOrigin)
    }

    func clearSiteDataAndReload() async {
        await activePage?.clearSiteDataAndReload()
    }

    func togglePreferredContentMode() {
        activePage?.togglePreferredContentMode()
    }

    func presentFind() {
        activePage?.presentFind()
    }

    func toggleReaderMode() {
        activePage?.toggleReaderMode()
    }

    func zoomIn() {
        guard activePage?.zoomIn() == true else { return }
        pageZoomFeedbackLabel = pageZoomLabel
        pageZoomFeedbackRevision &+= 1
    }

    func zoomOut() {
        guard activePage?.zoomOut() == true else { return }
        pageZoomFeedbackLabel = pageZoomLabel
        pageZoomFeedbackRevision &+= 1
    }

    func resetZoom() {
        guard activePage?.resetZoom() == true else { return }
        pageZoomFeedbackLabel = pageZoomLabel
        pageZoomFeedbackRevision &+= 1
    }

    func defaultPageZoomDidChange(to zoom: CGFloat) {
        var visited: Set<ObjectIdentifier> = []
        let retainedPages =
            Array(pagesByTabID.values)
            + transientLeases.values.compactMap { $0.value?.page }
        for page in retainedPages
        where visited.insert(ObjectIdentifier(page)).inserted {
            page.applyDefaultPageZoom(zoom)
        }
    }

    @discardableResult
    func copyPageLink() -> Bool {
        guard activePage?.copyPageLink() == true else { return false }
        urlCopyFeedbackRevision &+= 1
        return true
    }

    @discardableResult
    func copyPageLinkAsMarkdown() -> Bool {
        guard activePage?.copyPageLinkAsMarkdown() == true else { return false }
        urlCopyFeedbackRevision &+= 1
        return true
    }

    func pullFavicon(
        for tabID: TabID
    ) async -> (data: Data, iconAccent: BrowserTabIconAccent?)? {
        guard let page = pagesByTabID[tabID], let data = await page.pullFavicon() else {
            return nil
        }
        return (data, page.siteThemeIconAccent)
    }

    func pullFavicon(
        for tabID: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) async -> (data: Data, iconAccent: BrowserTabIconAccent?)? {
        guard let page = pagesByTabID[tabID],
            page.spaceID == assignment.spaceID,
            page.profileID == assignment.profileID,
            let data = await page.pullFavicon(),
            pagesByTabID[tabID] === page
        else { return nil }
        return (data, page.siteThemeIconAccent)
    }

    func printPage() {
        activePage?.printPage()
    }

    func exportPDF(to destination: MobileBrowserFileExportDestination) {
        activePage?.exportPDF(to: destination)
    }

    func exportWebArchive(to destination: MobileBrowserFileExportDestination) {
        activePage?.exportWebArchive(to: destination)
    }

    func cancelDownload(_ itemID: UUID) {
        downloadCenter.cancel(itemID)
    }

    func clearDownload(_ itemID: UUID) {
        downloadCenter.clear(itemID)
    }

    func exportDownload(
        _ itemID: UUID,
        to destination: MobileBrowserFileExportDestination
    ) {
        guard let item = downloadCenter.item(itemID),
            item.phase.isComplete,
            let destinationURL = item.destinationURL
        else { return }
        MobileBrowserDialogPresenter.exportDownloadedFile(
            at: destinationURL,
            to: destination
        )
    }

    /// Mobile leaves ordinary pages resident through warnings and releases one
    /// eligible least-recently-used page at a time under critical pressure.
    func handleMemoryPressure(
        _ level: MemoryPressureLevel,
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

    func containsResidentPage(for tabID: TabID) -> Bool {
        _ = residencyRevision
        return pagesByTabID[tabID] != nil
    }

    func containsResidentPage(
        matching assignment: BrowserTabRuntimeAssignment
    ) -> Bool {
        _ = residencyRevision
        guard let page = pagesByTabID[assignment.tabID] else { return false }
        return page.spaceID == assignment.spaceID
            && page.profileID == assignment.profileID
    }

    func siteThemeIconAccent(for tabID: TabID) -> BrowserTabIconAccent? {
        pagesByTabID[tabID]?.siteThemeIconAccent
    }

    func siteThemeIconAccent(
        matching assignment: BrowserTabRuntimeAssignment
    ) -> BrowserTabIconAccent? {
        guard let page = pagesByTabID[assignment.tabID],
            page.spaceID == assignment.spaceID,
            page.profileID == assignment.profileID
        else { return nil }
        return page.siteThemeIconAccent
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

    /// Builds a page for `tab` in `space`. `adoptedConfiguration` is WebKit's own
    /// popup configuration, which must be used exactly as handed over; passing it
    /// replaces the configuration the page would otherwise assemble and leaves
    /// the first navigation to WebKit.
    private func makeResidentPage(
        for tab: BrowserTab,
        in space: BrowserSpace,
        adoptedConfiguration: WKWebViewConfiguration? = nil,
        loadsInitialURL: Bool = true
    ) -> MobileBrowserPage {
        // Restoring WebKit's session state performs its own navigation, so the
        // page must not also start the tab's URL: whichever path runs, exactly one
        // navigation begins.
        let archivedState =
            loadsInitialURL && adoptedConfiguration == nil
            ? tab.url.flatMap {
                archivedInteractionState(
                    for: tab,
                    spaceID: space.id,
                    profileID: space.profile.id,
                    expecting: $0
                )
            }
            : nil
        let page = MobileBrowserPage(
            tab: tab,
            space: space,
            downloadCenter: downloadCenter,
            permissionCenter: permissionCenter,
            serverTrustOverrides: serverTrustOverrides,
            mediaSessionStore: mediaSessionStore,
            websiteDataStore: websiteDataStore(for: space.profile),
            adoptedConfiguration: adoptedConfiguration,
            contentRuleLists: contentRuleLists(for: space),
            allowsCredentialAccess: !browsingMode.isPrivate,
            isCredentialAccessEnabled: space.credentialPreferences.isEnabled,
            defaultPageZoom: pageZoomPreferences.defaultZoom,
            loadsInitialURL: loadsInitialURL
                && adoptedConfiguration == nil
                && archivedState == nil,
            loadHTTPAuthenticationCredential: { [loadHTTPAuthenticationCredential] protectionSpace in
                try await loadHTTPAuthenticationCredential(protectionSpace, space.id)
            },
            saveHTTPAuthenticationCredential: { [saveHTTPAuthenticationCredential] request in
                try await saveHTTPAuthenticationCredential(request, space.id)
            },
            linkDestinationHost: linkDestinationHost,
            openNewTab: openNewTab,
            openModifiedLink: openModifiedLink,
            openPeek: openPeek
        )
        page.host = self
        // Anything WebKit will not take falls through to the plain load the page
        // was told to skip.
        if let archivedState, let url = tab.url,
            !page.restoreInteractionState(archivedState, expecting: url)
        {
            page.load(url)
        }
        return page
    }

    private func tabID(for page: MobileBrowserPage) -> TabID? {
        pagesByTabID[page.tabID] === page ? page.tabID : nil
    }

    private func contentRuleLists(for space: BrowserSpace) -> [WKContentRuleList] {
        contentBlocking.ruleLists(for: space.browsingPreferences.contentBlockingPolicy)
    }

    /// Focuses a page that is already on screen, or brings one on screen beside
    /// the cards already there.
    ///
    /// Popup adoption and extension selection reach focus without going through
    /// `select`, one frame ahead of the store-driven reselection that settles the
    /// presented set properly. Adding the tab here rather than replacing the set
    /// is what keeps that frame from rendering a card with no page.
    private func activate(_ page: MobileBrowserPage, at time: Date) {
        var presented = presentedTabIDs
        if !presented.contains(page.tabID) {
            presented.append(page.tabID)
        }
        activate(page, presenting: presented, at: time)
    }

    /// Puts `presented` on screen in order with `page` focused.
    ///
    /// Unlike macOS, an unfocused card keeps its idle stamp: the carousel evicts
    /// off-screen members under critical pressure, and that decision is
    /// least-recently-used first, so a member that has never had focus still
    /// needs an age. A card leaving presentation keeps whatever stamp it already
    /// carried — it has been out of attention since then, not since now.
    private func activate(
        _ page: MobileBrowserPage,
        presenting presented: [TabID],
        at time: Date
    ) {
        if let activePage,
            activePage.tabID != page.tabID,
            pagesByTabID[activePage.tabID] != nil
        {
            inactiveSinceByTabID[activePage.tabID] = time
        }
        for departedTabID in Set(presentedTabIDs).subtracting(presented)
        where pagesByTabID[departedTabID] != nil {
            stampPreparedPageIfNeeded(departedTabID, at: time)
        }
        inactiveSinceByTabID[page.tabID] = nil
        // Guarded: `select` runs on every selection synchronization, and an
        // unconditional write would remount a card's host on changes that left
        // membership exactly as it was.
        if presentedTabIDs != presented {
            presentedTabIDs = presented
        }
        activePage = page
        // A page whose web-content process the system reclaimed while it was off
        // screen comes back here, where the memory it needs is memory the user is
        // about to look at.
        page.restoreWebContentIfNeeded()
    }

    @discardableResult
    private func releasePages(
        for tabIDs: Set<TabID>
    ) -> [BrowserSpaceDataReleaseProbe] {
        var releasedAnyPage = false
        var probes: [BrowserSpaceDataReleaseProbe] = []
        for tabID in tabIDs {
            forgetBackgroundPageObservation(for: tabID)
            if let page = pagesByTabID.removeValue(forKey: tabID) {
                probes.append(BrowserSpaceDataReleaseProbe(page))
                page.prepareForSpaceDeletion()
                releasedAnyPage = true
            }
        }
        if releasedAnyPage { residencyRevision &+= 1 }
        inactiveSinceByTabID = inactiveSinceByTabID.filter {
            !tabIDs.contains($0.key)
        }
        if let activePage, tabIDs.contains(activePage.tabID) {
            self.activePage = nil
        }
        // A released page cannot remain a presented card.
        if presentedTabIDs.contains(where: tabIDs.contains) {
            presentedTabIDs.removeAll { tabIDs.contains($0) }
        }
        return probes
    }

    /// Releases the pages memory pressure can afford to take back.
    ///
    /// Off-screen pages come first and almost always answer the question. Every
    /// presented card is ineligible in that sweep, focused or not — unloading a
    /// web view somebody is looking at is never a saving worth making. Only when
    /// that sweep finds nobody at all, and only at `.critical`, does the core's
    /// release plan open the far cards of the carousel.
    private func releaseInactivePages(for level: MemoryPressureLevel) async {
        // The core owns candidate eligibility and order; this store contributes
        // the residency facts and WebKit's own veto.
        let plan = BrowserCorePolicy.residencyReleasePlan(
            level: level,
            platform: .mobile,
            candidates: idleCandidates(),
            focusedIndex: activePage.flatMap { presentedTabIDs.firstIndex(of: $0.tabID) }
        )
        var eligibleTabIDs = await releasableTabIDs(among: plan.offScreen)
        eligibleTabIDs += nativeTabs.inactiveTabIDs(excluding: presentedTabIDs)

        if eligibleTabIDs.isEmpty {
            eligibleTabIDs = await releasableTabIDs(
                among: plan.presentedFallback,
                allowsPresentedPages: true
            )
        }

        let releaseLimit = BrowserCorePolicy.memoryPressureReleaseLimit(
            level: level,
            eligiblePageCount: eligibleTabIDs.count,
            platform: .mobile
        )
        for tabID in eligibleTabIDs.prefix(releaseLimit) {
            evictPage(tabID)
        }
    }

    /// Every resident page with an idle stamp, excluding the focused one, with
    /// the presentation facts the core needs to order and filter them.
    private func idleCandidates() -> [BrowserCorePolicy.ResidencyCandidate] {
        inactiveSinceByTabID.compactMap { tabID, inactiveSince in
            guard activePage?.tabID != tabID, let page = pagesByTabID[tabID] else {
                return nil
            }
            return BrowserCorePolicy.ResidencyCandidate(
                tabID: tabID,
                inactiveSince: inactiveSince,
                keepsPageLoaded: page.navigationContext?.keepsPageLoaded == true,
                presentedIndex: presentedTabIDs.firstIndex(of: tabID)
            )
        }
    }

    /// Asks each candidate's page whether it may be unloaded, preserving the
    /// caller's least-recently-used order.
    ///
    /// Everything is re-checked after the await: a page can be selected back onto
    /// the screen, or released outright, while WebKit is still answering for it.
    private func releasableTabIDs(
        among tabIDs: [TabID],
        allowsPresentedPages: Bool = false
    ) async -> [TabID] {
        var releasable: [TabID] = []
        for tabID in tabIDs {
            guard !Task.isCancelled else { return releasable }
            guard let page = pagesByTabID[tabID] else { continue }
            let decision = await residencyDecisionProvider(page, false)
            guard pagesByTabID[tabID] === page,
                tabID != activePage?.tabID,
                allowsPresentedPages || !presentedTabIDs.contains(tabID),
                decision.allowsAutomaticUnload
            else { continue }
            releasable.append(tabID)
        }
        return releasable
    }

    private func evictPage(_ tabID: TabID, preservingTabState: Bool = true) {
        nativeTabs.remove(tabID)
        forgetBackgroundPageObservation(for: tabID)
        if preservingTabState {
            archiveTabState(for: tabID)
        }
        guard let page = pagesByTabID.removeValue(forKey: tabID) else { return }
        page.prepareForSpaceDeletion()
        residencyRevision &+= 1
        inactiveSinceByTabID[tabID] = nil
    }

    private func forgetBackgroundPageObservation(for tabID: TabID) {
        backgroundPageAssignments[tabID] = nil
        backgroundPageSnapshots[tabID] = nil
    }

    /// Writes out the WebKit session state of every resident page. The app calls
    /// this when a scene stops being active, so state survives a termination
    /// before an inactive page reaches its idle deadline.
    func archiveResidentTabStates() {
        guard tabState.archivesResidentPages else { return }
        for tabID in pagesByTabID.keys {
            archiveTabState(for: tabID)
        }
    }

    func flushPendingTabStateWrites() async {
        await tabState.flushPendingWrites()
    }

    /// Capture stays on the main actor; the archive schedules disk writes.
    private func archiveTabState(for tabID: TabID) {
        guard let page = pagesByTabID[tabID] else { return }
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

    private func releaseTransientPages(for level: MemoryPressureLevel) {
        pruneTransientLeases()
        for lease in transientLeases.values.compactMap(\.value) {
            guard level.releasesActiveTransientPages || !lease.isActive else { continue }
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

    /// Listens for the kernel's own pressure events. UIKit's memory warning only
    /// reaches a foreground app and arrives late, so on iOS — where the system
    /// kills an app rather than swapping — this is the signal that gets ahead of a
    /// termination. It stays a thin wire: everything it decides is the level.
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

extension MobileBrowserPageStore: BrowserTabCopying {
    func sourceForTabCopy(_ source: BrowserTab, in space: BrowserSpace) -> BrowserTab {
        var observed = source
        if let page = pagesByTabID[source.id], page.spaceID == space.id, page.profileID == space.profile.id {
            observed.url = page.displayURL ?? source.url
            if let title = page.title, !title.isEmpty { observed.title = title }
        }
        return observed
    }

    func prepareTabCopy(from source: BrowserTab, to copy: inout BrowserTab, in space: BrowserSpace) {
        let state: Data?
        if let page = pagesByTabID[source.id], page.spaceID == space.id, page.profileID == space.profile.id {
            copy.url = page.displayURL ?? source.url
            if let title = page.title, !title.isEmpty { copy.title = title }
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

extension MobileBrowserPageStore: BrowserTabLinkProviding {
    func linkURL(for tab: BrowserTab, in space: BrowserSpace) -> URL? {
        guard tab.isWebPage else { return nil }
        guard let page = pagesByTabID[tab.id],
            page.spaceID == space.id,
            page.profileID == space.profile.id
        else { return tab.url }
        return page.url
    }
}
