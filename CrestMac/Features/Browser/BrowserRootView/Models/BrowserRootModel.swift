import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class BrowserRootModel {
    typealias SidebarMorphWait = @MainActor (Duration) async throws -> Void

    let browser: BrowserStore
    let sidebarInteraction: BrowserSidebarInteractionState
    let pages: BrowserPagePool
    let chrome: BrowserChromeState
    let spaceAccess: BrowserSpaceAccessController
    private let pageSession: BrowserPageSessionSynchronizer
    let windowState: BrowserWindowStateStore?
    private let layoutPersistence: BrowserWindowLayoutPersistence
    let startupBehavior: BrowserStartupBehavior
    let extensionSidebarWindowID: BrowserWindowID
    var extensionSidebar: BrowserExtensionSidebarHost?

    var address = ""
    var isAddressEditing = false
    /// Keep binding construction outside view evaluation: constructing a
    /// closure-backed binding reads its initial value. Reuse it so containers
    /// forwarding the binding do not observe the address themselves.
    @ObservationIgnored private(set) lazy var addressBinding = Binding<String>(
        get: { @MainActor [weak self] in self?.address ?? "" },
        set: { @MainActor [weak self] address in
            guard let self, self.address != address else { return }
            self.address = address
        }
    )
    @ObservationIgnored private(set) lazy var isAddressEditingBinding = Binding<Bool>(
        get: { @MainActor [weak self] in self?.isAddressEditing ?? false },
        set: { @MainActor [weak self] isEditing in
            guard let self, self.isAddressEditing != isEditing else { return }
            self.isAddressEditing = isEditing
        }
    )
    var hasRestoredExtensions = false
    var isURLCopiedFeedbackVisible = false
    var visiblePageZoomFeedbackLabel: String?
    var isFloatingSidebarPresented = false
    private(set) var isSidebarMorphing = false
    /// True while the page row is making the sidebar's dock available, before
    /// the persistent floating card adopts its docked appearance.
    private(set) var isSidebarApproachingDock = false
    private(set) var isSidebarSurfaceHovered = false
    private var sidebarMorphRevision = 0
    /// Cancels or awaits the current sidebar transition.
    @ObservationIgnored private(set) var sidebarMorphTask: Task<Void, Never>?
    /// Injectable phase timing for sidebar transitions.
    @ObservationIgnored
    var sidebarMorphWait: SidebarMorphWait = { try await Task.sleep(for: $0) }
    var isWindowFocused = true
    var sidebarWidthTransaction: BrowserSidebarWidthTransaction
    /// Live widths stay local until the divider drag commits.
    var splitWidthTransaction = BrowserSplitWidthTransaction(
        persistedFractions: [1]
    )
    /// The window owns the lift so its preview can outlive the source surface.
    let splitCardLift = BrowserSplitCardLiftState()

    init(
        browser: BrowserStore,
        pages: BrowserPagePool,
        chrome: BrowserChromeState,
        spaceAccess: BrowserSpaceAccessController,
        windowState: BrowserWindowStateStore?,
        startupBehavior: BrowserStartupBehavior,
        persistedSidebarWidth: CGFloat
    ) {
        self.browser = browser
        sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
        self.pages = pages
        self.chrome = chrome
        self.spaceAccess = spaceAccess
        pageSession = BrowserPageSessionSynchronizer(browser: browser, spaceAccess: spaceAccess)
        self.windowState = windowState
        layoutPersistence = BrowserWindowLayoutPersistence(windowState: windowState)
        extensionSidebarWindowID = windowState?.id ?? BrowserWindowID()
        self.startupBehavior = startupBehavior
        sidebarWidthTransaction = BrowserSidebarWidthTransaction(
            persistedWidth: persistedSidebarWidth
        )
        _ = addressBinding
        _ = isAddressEditingBinding
    }
}

// MARK: - Lifecycle

extension BrowserRootModel {
    func prepareBrowser() async {
        windowState?.captureSidebar(
            width: Double(sidebarWidth),
            isPresented: chrome.columnVisibility != .detailOnly
        )
        guard !hasRestoredExtensions else {
            BrowserExtensionStartupLog.skippedAlreadyRestored()
            return
        }
        await pages.restoreExtensions(in: browser.session)
        await pages.prepareContentBlocking()
        hasRestoredExtensions = true
        switch startupBehavior {
        case .lastActiveTab:
            synchronizeSelection()
        case .showStartPage:
            browser.presentStartPageForLaunch()
            address = ""
        }
    }

    func reconcileExtensions() {
        pages.reconcile(session: browser.session)
    }

    func extensionHostWindowFocusChanged(_ isFocused: Bool) {
        pages.extensionControllerPool.setHostWindowFocused(isFocused)
    }

    /// Republishes tab state that lives on the page rather than in the session,
    /// so `tabs.onUpdated` reports load progress and reader mode. Deliberately
    /// narrower than `reconcileExtensions()`, which also re-evaluates page
    /// residency and is far too heavy for a load beginning or ending.
    func reconcileExtensionTabActivity() {
        pages.extensionControllerPool.reconcileExtensionState(
            in: browser.session
        )
    }

    func reconcileTabIcons() {
        pages.reconcileTabIcons(in: browser.session)
    }

    func reconcileContentBlocking() {
        guard hasRestoredExtensions else { return }
        let session = browser.session
        Task { await pages.reconcileContentBlocking(in: session) }
    }

    func reconcileCredentialAccess() {
        pages.reconcileCredentialAccess(in: browser.session)
    }

    func reloadContentBlocking() {
        guard hasRestoredExtensions else { return }
        let session = browser.session
        Task { await pages.reloadContentBlocking(in: session) }
    }

    func relockProtectedSpaces(_ spaceIDs: Set<SpaceID>) {
        // The Space itself, not just its ID: relocking has to reach the
        // profile its archived tab state is filed under, and that state
        // outlives the resident pages an ID alone can find.
        for space in browser.session.spaces where spaceIDs.contains(space.id) {
            pages.relockProtectedSpace(space)
        }
    }
}

// MARK: - Bindings

extension BrowserRootModel {
    var isWindowFocusedBinding: Binding<Bool> {
        Binding(
            get: { self.isWindowFocused },
            set: { isFocused in
                guard self.isWindowFocused != isFocused else { return }
                self.isWindowFocused = isFocused
            }
        )
    }
}

// MARK: - Page Synchronization

extension BrowserRootModel {
    private var selectedPage: BrowserPage? {
        guard let space = browser.selectedSpace,
            !spaceAccess.isLocked(space),
            let tab = browser.selectedTab
        else { return nil }
        return pages.activePage(
            matching: BrowserTabRuntimeAssignment(
                tabID: tab.id, spaceID: space.id, profileID: space.profile.id
            )
        )
    }

    var windowTitle: String {
        guard let space = browser.selectedSpace,
            !spaceAccess.isLocked(space),
            let tab = browser.selectedTab
        else { return ProductIdentity.name }
        if tab.isStartPage { return String(localized: "Start Page") }
        if let title = BrowserTab.resolvedCustomTitle(tab.customTitle) { return title }
        return BrowserWindowTitle.resolve(page: selectedPage, storedTitle: tab.title, url: tab.url)
    }

    func synchronizePageMetadata() {
        guard let page = selectedPage, let source = selectedTabAssignment,
            let updatedAddress = pageSession.synchronize(page.metadata, matching: source)
        else { return }
        if !isAddressEditing { address = updatedAddress }
    }

    func recordCompletedNavigation() {
        guard let page = selectedPage, page.url != nil, let source = selectedTabAssignment else { return }
        synchronizePageMetadata()
        guard let space = pageSession.recordCompletedNavigation(page.metadata, matching: source) else { return }
        Task { await pages.styleVisitedLinks(in: space) }
    }

}

// MARK: - Navigation

extension BrowserRootModel {
    /// Distinguishes Space changes from tab changes.
    var selectionSnapshot: BrowserRootSelectionSnapshot {
        BrowserRootSelectionSnapshot(
            tabID: browser.selectedTab?.id,
            spaceID: browser.session.selectedSpaceID
        )
    }

    var selectedSpaceIsLocked: Bool {
        guard let space = browser.selectedSpace else { return false }
        return spaceAccess.isLocked(space)
    }

    var lockedSpaceIDs: Set<SpaceID> {
        Set(
            browser.session.spaces.compactMap { space in
                spaceAccess.isLocked(space) ? space.id : nil
            }
        )
    }

    func openNewTab() {
        chrome.openNewTab(
            isStartPageSelected: browser.selectedTab?.isStartPage == true
        )
    }

    func submitAddress() {
        guard
            let url = AddressResolver.resolve(
                address,
                searchProvider: browser.selectedSpace?.browsingPreferences.searchProvider
                    ?? .google
            )
        else { return }
        browser.navigateSelectedTab(to: url)
        pages.load(url)
        address = url.absoluteString
        isAddressEditing = false
        AddressFocusAction.resign()
    }

    func synchronizeAfterSelectionChange() {
        extensionSidebar?.reconcile()
        guard hasRestoredExtensions else { return }
        isAddressEditing = false
        AddressFocusAction.resign()
        synchronizeSelection()
    }

    func synchronizeAfterSpaceChange() {
        extensionSidebar?.reconcile()
        guard hasRestoredExtensions else { return }
        isAddressEditing = false
        AddressFocusAction.resign()
        if selectedSpaceIsLocked || !pages.isPresentingSelection(in: browser.session) {
            if selectedSpaceIsLocked {
                pages.deactivatePagePresentation()
            } else {
                pages.selectSpace(in: browser)
            }
            address = selectedSpaceIsLocked ? "" : browser.selectedTab?.url?.absoluteString ?? ""
            return
        }
        address = browser.selectedTab?.url?.absoluteString ?? ""
    }

    func synchronizeAfterLockChange() {
        extensionSidebar?.reconcile()
        guard hasRestoredExtensions else { return }
        synchronizeSelection()
    }

    func synchronizeSelection() {
        browser.consumeMovedTabActivation()
        guard !selectedSpaceIsLocked else {
            pages.deactivatePagePresentation()
            address = ""
            return
        }
        if let tab = browser.selectedTab, tab.isStartPage,
            browser.selectedSpace?.splitGroup(containing: tab.id) == nil
        {
            pages.deactivatePagePresentation()
        } else {
            pages.select(session: browser.session)
        }
        address = browser.selectedTab?.url?.absoluteString ?? ""
    }

    func handleAuxiliaryMouseAction(
        _ action: BrowserSidebarMouseButtonAction
    ) {
        let direction: BrowserSpaceSwipeDirection
        switch action {
        case .previousSpace:
            direction = .previous
        case .nextSpace:
            direction = .next
        }
        guard browser.selectAdjacentSpace(direction) != nil else { return }
        pages.selectSpace(in: browser)
    }
}

// MARK: - Sidebar

extension BrowserRootModel {
    var sidebarPresentation: BrowserSidebarPresentation {
        BrowserSidebarPresentationPolicy.presentation(
            columnVisibility: chrome.columnVisibility,
            isFloatingSidebarPresented: isFloatingSidebarPresented
        )
    }

    var sidebarWidth: CGFloat {
        sidebarWidthTransaction.width
    }

    var sidebarWidthBinding: Binding<CGFloat> {
        Binding(
            get: { self.sidebarWidthTransaction.width },
            set: { self.sidebarWidthTransaction.resize(to: $0) }
        )
    }

    func restoreSidebarWidth(_ width: CGFloat) {
        layoutPersistence.restoreSidebarWidth(width, transaction: &sidebarWidthTransaction)
    }

    func commitSidebarWidth(_ width: CGFloat) -> CGFloat? {
        layoutPersistence.commitSidebarWidth(width, transaction: &sidebarWidthTransaction)
    }

    func hideSidebar(reduceMotion: Bool) {
        chrome.utilityPresentation.dismiss()
        guard !reduceMotion else {
            cancelSidebarMorph()
            isFloatingSidebarPresented = isSidebarSurfaceHovered
            chrome.hideSidebar()
            return
        }

        let revision = beginSidebarMorph()
        sidebarMorphTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                !Task.isCancelled,
                self.sidebarMorphRevision == revision
            else { return }
            withAnimation(
                self.accessibleAnimation(CrestMotion.sidebarMorph, reduceMotion)
            ) {
                self.isFloatingSidebarPresented = true
                self.chrome.hideSidebar()
            }
            try? await self.sidebarMorphWait(
                CrestMotion.sidebarMorphCompletionDelay
            )
            guard !Task.isCancelled,
                self.finishSidebarMorph(revision),
                self.sidebarPresentation == .floating
            else { return }
            self.dismissFloatingSidebarIfInteractionAllows(
                reduceMotion: reduceMotion
            )
        }
    }

    func toggleSidebar(reduceMotion: Bool) {
        switch sidebarPresentation.sidebarToggleAction {
        case .hide:
            hideSidebar(reduceMotion: reduceMotion)
        case .dock:
            guard !reduceMotion else {
                cancelSidebarMorph()
                isFloatingSidebarPresented = false
                chrome.showSidebar()
                return
            }
            let revision = beginSidebarMorph()
            sidebarMorphTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard let self,
                    !Task.isCancelled,
                    self.sidebarMorphRevision == revision
                else { return }
                withAnimation(
                    self.accessibleAnimation(
                        CrestMotion.sidebarDockApproach,
                        reduceMotion
                    )
                ) {
                    self.isSidebarApproachingDock = true
                }
                try? await self.sidebarMorphWait(
                    CrestMotion.sidebarDockApproachCompletionDelay
                )
                guard !Task.isCancelled,
                    self.sidebarMorphRevision == revision
                else { return }
                withAnimation(
                    self.accessibleAnimation(
                        CrestMotion.sidebarDockAttachment,
                        reduceMotion
                    )
                ) {
                    self.isFloatingSidebarPresented = false
                    self.chrome.showSidebar()
                }
                try? await self.sidebarMorphWait(
                    CrestMotion.sidebarDockAttachmentCompletionDelay
                )
                guard !Task.isCancelled,
                    self.sidebarMorphRevision == revision
                else { return }
                withTransaction(Transaction(animation: nil)) {
                    self.isSidebarApproachingDock = false
                }
                _ = self.finishSidebarMorph(revision)
            }
        }
    }

    func presentFloatingSidebar(reduceMotion: Bool) {
        guard chrome.columnVisibility == .detailOnly else { return }
        cancelSidebarMorph()
        withAnimation(
            accessibleAnimation(CrestMotion.floatingPane, reduceMotion)
        ) {
            isFloatingSidebarPresented = true
        }
    }

    func dismissFloatingSidebar(reduceMotion: Bool) {
        cancelSidebarMorph()
        if sidebarPresentation == .floating {
            chrome.utilityPresentation.dismiss()
        }
        withAnimation(
            accessibleAnimation(CrestMotion.sidebarRetreat, reduceMotion)
        ) {
            isFloatingSidebarPresented = false
        }
        isSidebarSurfaceHovered = false
    }

    func sidebarSurfaceHoverChanged(
        _ isHovering: Bool,
        reduceMotion: Bool
    ) {
        isSidebarSurfaceHovered = isHovering
        guard sidebarPresentation == .floating, !isHovering else { return }
        dismissFloatingSidebarIfInteractionAllows(reduceMotion: reduceMotion)
    }

    func sidebarInteractionChanged(
        _ isActive: Bool,
        reduceMotion: Bool
    ) {
        guard !isActive else { return }
        dismissFloatingSidebarIfInteractionAllows(reduceMotion: reduceMotion)
    }

    func columnVisibilityChanged(reduceMotion: Bool) {
        guard chrome.columnVisibility != .detailOnly else {
            chrome.utilityPresentation.dismiss()
            return
        }
        guard !isSidebarMorphing else { return }
        dismissFloatingSidebar(reduceMotion: reduceMotion)
    }

    private func beginSidebarMorph() -> Int {
        sidebarMorphTask?.cancel()
        sidebarMorphTask = nil
        sidebarMorphRevision += 1
        withTransaction(Transaction(animation: nil)) {
            isSidebarMorphing = true
        }
        return sidebarMorphRevision
    }

    private func dismissFloatingSidebarIfInteractionAllows(
        reduceMotion: Bool
    ) {
        guard !isSidebarMorphing,
            !isSidebarSurfaceHovered,
            !chrome.utilityPresentation.isSidebarInteractionActive
        else { return }
        dismissFloatingSidebar(reduceMotion: reduceMotion)
    }

    @discardableResult
    private func finishSidebarMorph(_ revision: Int) -> Bool {
        guard revision == sidebarMorphRevision else { return false }
        sidebarMorphTask = nil
        withTransaction(Transaction(animation: nil)) {
            isSidebarMorphing = false
        }
        return true
    }

    private func cancelSidebarMorph() {
        sidebarMorphTask?.cancel()
        sidebarMorphTask = nil
        sidebarMorphRevision += 1
        withTransaction(Transaction(animation: nil)) {
            isSidebarMorphing = false
            isSidebarApproachingDock = false
        }
    }
}

// MARK: - Split Layout

extension BrowserRootModel {
    /// The cards the content area presents for the current selection.
    ///
    /// Derived from the session rather than read out of
    /// `BrowserPagePool.presentedTabIDs`: both answer the same
    /// `presentedSplitMembers(for:)` question, and taking the store's answer is
    /// what keeps SwiftUI observing the thing that actually changes when
    /// membership does.
    var presentedSplitMembers: [BrowserTab] {
        guard let space = browser.selectedSpace else { return [] }
        return space.presentedSplitMembers(for: browser.selectedTab?.id)
    }

    /// The group the presented cards belong to, or `nil` when one tab presents
    /// alone. Column fractions are stored per group, so a lone tab has no
    /// layout to store.
    var presentedSplitGroupID: SplitGroupID? {
        guard let space = browser.selectedSpace,
            let selectedTabID = browser.selectedTab?.id
        else { return nil }
        return space.splitGroup(containing: selectedTabID)
    }

    var splitWidthTransactionBinding: Binding<BrowserSplitWidthTransaction> {
        Binding(
            get: { self.splitWidthTransaction },
            set: { self.splitWidthTransaction = $0 }
        )
    }

    func seedSplitColumnFractions() {
        layoutPersistence.seedSplitLayout(
            groupID: presentedSplitGroupID, memberCount: presentedSplitMembers.count,
            transaction: &splitWidthTransaction
        )
    }

    func commitSplitColumnFractions(_ fractions: [Double]) {
        layoutPersistence.commitSplitLayout(fractions, groupID: presentedSplitGroupID)
    }

    func focusSplitCard(_ tabID: TabID) {
        guard tabID != browser.selectedTab?.id,
            presentedSplitMembers.contains(where: { $0.id == tabID })
        else { return }
        browser.selectTab(tabID)
    }
}

// MARK: - Command Palette

extension BrowserRootModel {
    var selectedTabAssignment: BrowserTabRuntimeAssignment? {
        guard let space = browser.selectedSpace, let tab = browser.selectedTab else {
            return nil
        }
        return BrowserTabRuntimeAssignment(
            tabID: tab.id,
            spaceID: space.id,
            profileID: space.profile.id
        )
    }

    func isPaletteSourceAvailable(
        _ source: BrowserTabRuntimeAssignment
    ) -> Bool {
        BrowserCommandPaletteActionPolicy.isSourceAvailable(
            source,
            in: browser,
            accessController: spaceAccess
        )
    }

    @discardableResult
    func selectPaletteTab(
        from source: BrowserTabRuntimeAssignment,
        to target: BrowserTabRuntimeAssignment
    ) -> Bool {
        guard
            let destination = BrowserCommandPaletteActionPolicy.target(
                target,
                from: source,
                in: browser,
                accessController: spaceAccess
            )
        else { return false }
        browser.selectSpace(destination.space.id)
        browser.selectTab(destination.tab.id)
        pages.select(session: browser.session)
        address = browser.selectedTab?.url?.absoluteString ?? ""
        return true
    }

    @discardableResult
    func openPaletteURL(
        _ url: URL,
        mode: BrowserCommandPaletteMode,
        from source: BrowserTabRuntimeAssignment
    ) -> Bool {
        guard
            BrowserCommandPaletteActionPolicy.isSourceAvailable(
                source,
                in: browser,
                accessController: spaceAccess
            )
        else { return false }
        switch mode {
        case .editLocation:
            browser.navigateSelectedTab(to: url)
        case .newTab:
            if browser.selectedTab?.isStartPage == true {
                browser.navigateSelectedTab(to: url)
            } else {
                guard
                    browser.openNewTab(
                        url: url,
                        matching: BrowserSpaceRuntimeAssignment(
                            spaceID: source.spaceID,
                            profileID: source.profileID
                        )
                    ) != nil
                else { return false }
            }
        }
        pages.select(session: browser.session)
        pages.load(url)
        address = url.absoluteString
        return true
    }
}

// MARK: - Feedback

extension BrowserRootModel {
    func presentURLCopyFeedback(revision: Int, reduceMotion: Bool) {
        guard revision > 0 else { return }
        withAnimation(
            accessibleAnimation(CrestMotion.feedbackPresentation, reduceMotion)
        ) {
            visiblePageZoomFeedbackLabel = nil
            isURLCopiedFeedbackVisible = true
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: BrowserRootMetrics.urlCopyFeedbackDuration)
            guard let self,
                self.chrome.urlCopyFeedbackRevision == revision
            else { return }
            withAnimation(
                self.accessibleAnimation(CrestMotion.dismissal, reduceMotion)
            ) {
                self.isURLCopiedFeedbackVisible = false
            }
        }
    }

    func presentPageZoomFeedback(revision: Int, reduceMotion: Bool) {
        guard revision > 0 else { return }
        withAnimation(
            accessibleAnimation(CrestMotion.feedbackPresentation, reduceMotion)
        ) {
            isURLCopiedFeedbackVisible = false
            visiblePageZoomFeedbackLabel = chrome.pageZoomFeedbackLabel
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: BrowserRootMetrics.urlCopyFeedbackDuration)
            guard let self,
                self.chrome.pageZoomFeedbackRevision == revision
            else { return }
            withAnimation(
                self.accessibleAnimation(CrestMotion.dismissal, reduceMotion)
            ) {
                self.visiblePageZoomFeedbackLabel = nil
            }
        }
    }
}

// MARK: - Animation

extension BrowserRootModel {
    func accessibleAnimation(
        _ animation: Animation,
        _ reduceMotion: Bool
    ) -> Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            animation,
            reduceMotion: reduceMotion
        )
    }
}

// MARK: - Downloads

extension BrowserRootModel {
    var selectedUtilityDownloads: [BrowserDownloadItem] {
        guard let profileID = browser.selectedSpace?.profile.id else { return [] }
        return pages.downloadCenter.items(for: profileID)
    }

    var newUtilityDownloads: [BrowserDownloadItem] {
        guard let profileID = browser.selectedSpace?.profile.id else { return [] }
        return pages.downloadCenter.unacknowledgedItems(for: profileID)
    }
}
