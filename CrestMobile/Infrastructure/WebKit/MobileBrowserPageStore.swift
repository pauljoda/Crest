import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

@Observable
@MainActor
final class MobileBrowserPageStore: BrowserSpaceDataDeleting, MobileBrowserPageHosting {
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

    /// One resident page memory pressure may consider, with the idle stamp its
    /// least-recently-used ordering comes from.
    private typealias IdlePageCandidate = (
        tabID: TabID,
        inactiveSince: Date,
        page: MobileBrowserPage
    )

    /// The focused card: the one page the toolbar, find bar, navigation
    /// controls, and every lifecycle observer speak for. Split View adds cards
    /// beside it without adding a second focus.
    private(set) var activePage: MobileBrowserPage?

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
    private(set) var residencyRevision = 0
    private(set) var urlCopyFeedbackRevision = 0
    private(set) var pageZoomFeedbackLabel = "100%"
    private(set) var pageZoomFeedbackRevision = 0
    private(set) var contentBlockingErrorDescription: String?
    let downloadCenter: BrowserDownloadCenter
    let downloadRiskConfirmation: MobileDownloadRiskConfirmationCoordinator
    let permissionCenter: BrowserSitePermissionCenter
    let serverTrustOverrides = BrowserServerTrustOverrideStore()

    @ObservationIgnored private var pagesByTabID: [TabID: MobileBrowserPage] = [:]
    @ObservationIgnored private var inactiveSinceByTabID: [TabID: Date] = [:]
    @ObservationIgnored private var ephemeralDataStores: [UUID: WKWebsiteDataStore] = [:]
    @ObservationIgnored private let popupTabHost: BrowserPopupTabHost
    @ObservationIgnored private let openNewTab: (URL) -> Void
    @ObservationIgnored private let openModifiedLink: (URL, SpaceID, Bool) -> Void
    @ObservationIgnored private let openPeek: (BrowserPeekRequest) -> Void
    @ObservationIgnored private let stagePeek: ((BrowserPeekRequest) -> Void)?
    @ObservationIgnored private let commitPeek: ((BrowserPeekRequest) -> Void)?
    @ObservationIgnored private let cancelStagedPeek: ((UUID) -> Void)?
    @ObservationIgnored private let residencyDecisionProvider: ResidencyDecisionProvider
    @ObservationIgnored private var memoryPressureReleaseTask: Task<Void, Never>?
    @ObservationIgnored private let browsingMode: BrowserBrowsingMode
    @ObservationIgnored private let usesEphemeralWebsiteDataStores: Bool
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
    @ObservationIgnored private var transientLeases: [UUID: WeakMobileBrowserTransientPageLease] = [:]
    @ObservationIgnored private var spacesReleasingData: Set<SpaceID> = []
    @ObservationIgnored private var spacesDeletingData: Set<SpaceID> = []
    /// Where unloaded tabs leave their WebKit session state. Always nil for a
    /// private store, so private browsing cannot write one even if an archive is
    /// handed in.
    @ObservationIgnored private let tabStateArchive: (any BrowserTabStateArchiving)?
    @ObservationIgnored private var lastPrunedTabIDsByProfileID: [UUID: Set<TabID>] = [:]

    init(
        monitorsMemoryPressure: Bool = false,
        browsingMode: BrowserBrowsingMode = .standard,
        usesEphemeralWebsiteDataStores: Bool =
            BrowserLaunchIsolationPolicy.requiresIsolation(.current),
        permissionCenter: BrowserSitePermissionCenter = BrowserSitePermissionCenter(),
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
        openModifiedLink: @escaping (URL, SpaceID, Bool) -> Void = { _, _, _ in },
        openPeek: @escaping (BrowserPeekRequest) -> Void = { _ in },
        stagePeek: ((BrowserPeekRequest) -> Void)? = nil,
        commitPeek: ((BrowserPeekRequest) -> Void)? = nil,
        cancelStagedPeek: ((UUID) -> Void)? = nil,
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
        self.tabStateArchive =
            self.usesEphemeralWebsiteDataStores
            ? nil
            : tabStateArchive
        self.popupTabHost = popupTabHost
        self.permissionCenter = permissionCenter
        self.loadHTTPAuthenticationCredential = loadHTTPAuthenticationCredential
        self.saveHTTPAuthenticationCredential = saveHTTPAuthenticationCredential
        self.websiteDataStoreRemover = websiteDataStoreRemover
        self.contentRuleListProvider = contentRuleListProvider
        self.openNewTab = openNewTab
        self.openModifiedLink = openModifiedLink
        self.openPeek = openPeek
        self.stagePeek = stagePeek
        self.commitPeek = commitPeek
        self.cancelStagedPeek = cancelStagedPeek
        let downloadRiskConfirmation = MobileDownloadRiskConfirmationCoordinator()
        self.downloadRiskConfirmation = downloadRiskConfirmation
        downloadCenter = BrowserDownloadCenter(
            ledger: downloadLedger,
            promptForCredentials: { prompt, spaceName in
                await MobileBrowserDialogPresenter.presentHTTPAuthentication(
                    prompt: prompt,
                    spaceName: spaceName
                )
            },
            allowsCredentialSaving: !browsingMode.isPrivate,
            loadCredential: loadHTTPAuthenticationCredential,
            saveCredential: saveHTTPAuthenticationCredential,
            approveRiskyDownload: { assessment, sourceURL, spaceName in
                await downloadRiskConfirmation.requestApproval(
                    assessment: assessment,
                    sourceURL: sourceURL,
                    spaceName: spaceName
                )
            },
            permissionCenter: permissionCenter,
            approveAutomaticDownload: { filename, origin, spaceName in
                await MobileBrowserDialogPresenter.presentAutomaticDownloadPermission(
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
        // iOS scenes are not the resizable, positionable windows the
        // `browser.windows` geometry APIs describe, so Crest reports none.
        .unavailable
    }

    private func extensionPage(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> MobileBrowserPage? {
        guard let page = pagesByTabID[tabID], page.spaceID == spaceID else {
            return nil
        }
        return page
    }

    func prepareExtensionSelection(session: BrowserSession) {
        _ = prepareSelectedPage(in: session, at: .now)
    }

    var retainedTransientPageCount: Int {
        pruneTransientLeases()
        return transientLeases.values.compactMap(\.value).filter { $0.page != nil }.count
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
    /// navigation, so a background filter-list refresh cannot reload every resident
    /// tab out from under someone who is typing in one of them. The single
    /// exception is the active page, and only when the user just changed the
    /// protection level of the Space it belongs to — that request came with an
    /// expectation of seeing the answer.
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
        for (tabID, page) in pagesByTabID {
            // Every card of a split, not only the focused one: the request came
            // with an expectation of seeing the answer, and seeing it on one of
            // three visible cards would read as a bug.
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
        // A Peek is never the active page, so its rules change under the same
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
    /// Space changed, so launching — where pages can be built before the rule
    /// lists finish compiling — never reloads the page it just restored.
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

    func select(session: BrowserSession) {
        select(session: session, at: .now)
    }

    func select(session: BrowserSession, at time: Date) {
        if !prepareSelectedPage(in: session, at: time) {
            deactivatePagePresentation(at: time)
        }
        reconcileCredentialAccess(in: session)
    }

    private func prepareSelectedPage(
        in session: BrowserSession,
        at time: Date
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
            tabStateArchive?.removeState(
                profileID: mismatched.profileID,
                tabID: tab.id
            )
            mismatched.prepareForSpaceDeletion()
            inactiveSinceByTabID[tab.id] = nil
        }

        let page = makeResidentPage(for: tab, in: space)
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
        in session: BrowserSession,
        at time: Date = .now
    ) -> MobileBrowserPage? {
        guard let space = session.selectedSpace,
            let tab = space.tabs.first(where: { $0.id == tabID }),
            !spacesReleasingData.contains(space.id),
            !spacesDeletingData.contains(space.id)
        else { return nil }

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
            tabStateArchive?.removeState(
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
            pagesByTabID.compactMap { tabID, page in
                guard let assignment = assignments[tabID],
                    assignment.spaceID == page.spaceID,
                    assignment.profileID == page.profileID
                else {
                    return tabID
                }
                return nil
            })
        releasePages(for: invalidTabIDs)
        for (tabID, page) in pagesByTabID {
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
        for page in pagesByTabID.values {
            page.prepareForSpaceDeletion()
        }
        pagesByTabID.removeAll()
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

    func makeTransientPageLease(
        url: URL,
        in space: BrowserSpace,
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
        let rebuild: () -> MobileBrowserPage? = { [weak self] in
            guard let self,
                canHostTransientPage(matching: assignment)
            else { return nil }
            return makeTransientPage(tab: transientTab, in: space)
        }
        let lease = MobileBrowserTransientPageLease(
            page: initialPage,
            url: url,
            contentBlockingPolicy:
                space.browsingPreferences.contentBlockingPolicy,
            balancedContentRuleLists: balancedContentRuleLists ?? [],
            rebuild: rebuild,
            userActivity: onUserActivity,
            onDownloadOnlyNavigation: onDownloadOnlyNavigation
        )
        transientLeases[lease.id] = WeakMobileBrowserTransientPageLease(lease)
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
            loadsInitialURL: false,
            loadHTTPAuthenticationCredential: { [loadHTTPAuthenticationCredential] protectionSpace in
                try await loadHTTPAuthenticationCredential(protectionSpace, space.id)
            },
            saveHTTPAuthenticationCredential: { [saveHTTPAuthenticationCredential] request in
                try await saveHTTPAuthenticationCredential(request, space.id)
            },
            openNewTab: openNewTab,
            openModifiedLink: openModifiedLink,
            openPeek: openPeek,
            stagePeek: stagePeek,
            commitPeek: commitPeek,
            cancelStagedPeek: cancelStagedPeek
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
        opener: MobileBrowserPage
    ) -> WKWebView? {
        guard tabID(for: opener) != nil,
            !spacesReleasingData.contains(opener.spaceID),
            !spacesDeletingData.contains(opener.spaceID),
            let registration = popupTabHost.openTab(requestedURL, opener.spaceID),
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
        activate(page, at: .now)
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
        guard let page = pagesByTabID[tabID],
            page.spaceID == assignment.spaceID,
            page.profileID == assignment.profileID
        else { return false }
        unloadPage(for: tabID)
        return true
    }

    /// Releases only the resident WebKit pages owned by one Space. Normal
    /// Space switching preserves residency; this is the residency half of a
    /// protected Space returning to its locked state.
    ///
    /// Nothing is archived on the way out, unlike an idle or manual unload: a locked Space is
    /// meant to leave nothing behind, and `relockProtectedSpace(_:)` is the
    /// entry point that also clears what earlier unloads already wrote.
    func unloadPages(in spaceID: SpaceID) {
        let tabIDs = Set(
            pagesByTabID.compactMap { tabID, page in
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
        guard let item = downloadCenter.items.first(where: { $0.id == itemID }),
            item.state == .finished,
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
        adoptedConfiguration: WKWebViewConfiguration? = nil
    ) -> MobileBrowserPage {
        // Restoring WebKit's session state performs its own navigation, so the
        // page must not also start the tab's URL: whichever path runs, exactly one
        // navigation begins.
        let archivedState =
            adoptedConfiguration == nil
            ? tab.url.flatMap {
                archivedInteractionState(
                    for: tab,
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
            websiteDataStore: websiteDataStore(for: space.profile),
            adoptedConfiguration: adoptedConfiguration,
            contentRuleLists: contentRuleLists(for: space),
            allowsCredentialAccess: !browsingMode.isPrivate,
            isCredentialAccessEnabled: space.credentialPreferences.isEnabled,
            loadsInitialURL: adoptedConfiguration == nil && archivedState == nil,
            loadHTTPAuthenticationCredential: { [loadHTTPAuthenticationCredential] protectionSpace in
                try await loadHTTPAuthenticationCredential(protectionSpace, space.id)
            },
            saveHTTPAuthenticationCredential: { [saveHTTPAuthenticationCredential] request in
                try await saveHTTPAuthenticationCredential(request, space.id)
            },
            openNewTab: openNewTab,
            openModifiedLink: openModifiedLink,
            openPeek: openPeek,
            stagePeek: stagePeek,
            commitPeek: commitPeek,
            cancelStagedPeek: cancelStagedPeek
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
        guard space.browsingPreferences.contentBlockingPolicy == .balanced else {
            return []
        }
        return balancedContentRuleLists ?? []
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
        // Locking a Space reaches here, so a released page never stays a card.
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
    /// that sweep finds nobody at all, and only at `.critical`, does
    /// `BrowserPresentedPageReleasePolicy` open the far cards of the carousel.
    private func releaseInactivePages(for level: BrowserMemoryPressureLevel) async {
        let candidates = idleCandidatesByLeastRecentlyUsed()
        let offScreen = candidates.filter { !presentedTabIDs.contains($0.tabID) }
        var eligibleTabIDs = await releasableTabIDs(among: offScreen)

        if eligibleTabIDs.isEmpty {
            let fallbackTabIDs = Set(
                BrowserPresentedPageReleasePolicy.fallbackReleasableTabIDs(
                    presentedTabIDs: presentedTabIDs,
                    focusedTabID: activePage?.tabID,
                    level: level,
                    hasOtherReleasablePages: false
                )
            )
            eligibleTabIDs = await releasableTabIDs(
                among: candidates.filter { fallbackTabIDs.contains($0.tabID) },
                allowsPresentedPages: true
            )
        }

        let releaseLimit = BrowserMemoryPressureReleasePolicy.releaseLimit(
            for: level,
            eligiblePageCount: eligibleTabIDs.count,
            platform: .mobile
        )
        for tabID in eligibleTabIDs.prefix(releaseLimit) {
            evictPage(tabID)
        }
    }

    /// Every resident page with an idle stamp, oldest first, excluding the
    /// focused one. Ties break on tab identity so a squeeze is deterministic.
    private func idleCandidatesByLeastRecentlyUsed() -> [IdlePageCandidate] {
        inactiveSinceByTabID.compactMap {
            tabID,
            inactiveSince -> IdlePageCandidate? in
            guard activePage?.tabID != tabID, let page = pagesByTabID[tabID] else {
                return nil
            }
            return (tabID: tabID, inactiveSince: inactiveSince, page: page)
        }.sorted {
            if $0.inactiveSince != $1.inactiveSince {
                return $0.inactiveSince < $1.inactiveSince
            }
            return $0.tabID.rawValue.uuidString < $1.tabID.rawValue.uuidString
        }
    }

    /// Asks each candidate's page whether it may be unloaded, preserving the
    /// caller's least-recently-used order.
    ///
    /// Everything is re-checked after the await: a page can be selected back onto
    /// the screen, or released outright, while WebKit is still answering for it.
    private func releasableTabIDs(
        among candidates: [IdlePageCandidate],
        allowsPresentedPages: Bool = false
    ) async -> [TabID] {
        var releasable: [TabID] = []
        for candidate in candidates {
            guard !Task.isCancelled else { return releasable }
            let decision = await residencyDecisionProvider(candidate.page, false)
            guard pagesByTabID[candidate.tabID] === candidate.page,
                candidate.tabID != activePage?.tabID,
                allowsPresentedPages || !presentedTabIDs.contains(candidate.tabID),
                decision.allowsAutomaticUnload
            else { continue }
            releasable.append(candidate.tabID)
        }
        return releasable
    }

    private func evictPage(_ tabID: TabID, preservingTabState: Bool = true) {
        if preservingTabState {
            archiveTabState(for: tabID)
        }
        guard let page = pagesByTabID.removeValue(forKey: tabID) else { return }
        page.prepareForSpaceDeletion()
        residencyRevision &+= 1
        inactiveSinceByTabID[tabID] = nil
    }

    /// Writes out the WebKit session state of every resident page. The app calls
    /// this when a scene stops being active, so state survives a termination
    /// before an inactive page reaches its idle deadline.
    func archiveResidentTabStates() {
        guard tabStateArchive != nil else { return }
        for tabID in pagesByTabID.keys {
            archiveTabState(for: tabID)
        }
    }

    func flushPendingTabStateWrites() async {
        await tabStateArchive?.flushPendingWrites()
    }

    /// Reading `interactionState` is main-actor work; the archive takes the write
    /// off the main thread from here.
    private func archiveTabState(for tabID: TabID) {
        guard let tabStateArchive, let page = pagesByTabID[tabID] else { return }
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
