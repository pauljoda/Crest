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
    let windowState: BrowserWindowStateStore?
    private let layoutPersistence: BrowserWindowLayoutPersistence
    let startupBehavior: BrowserStartupBehavior

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
    var isPrepared = false
    @ObservationIgnored private var isPreparingBrowser = false
    var visibleNotice: BrowserNotice?
    var isFloatingSidebarPresented: Bool {
        get { observed(\.isFloatingSidebarPresentedStorage, as: \.isFloatingSidebarPresented) }
        set { publish(newValue, into: \.isFloatingSidebarPresentedStorage, as: \.isFloatingSidebarPresented) }
    }
    @ObservationIgnored private var isFloatingSidebarPresentedStorage = false
    private(set) var isSidebarMorphing: Bool {
        get { observed(\.isSidebarMorphingStorage, as: \.isSidebarMorphing) }
        set { publish(newValue, into: \.isSidebarMorphingStorage, as: \.isSidebarMorphing) }
    }
    @ObservationIgnored private var isSidebarMorphingStorage = false
    /// True while the page row is making the sidebar's dock available, before
    /// the persistent floating card adopts its docked appearance.
    private(set) var isSidebarApproachingDock: Bool {
        get { observed(\.isSidebarApproachingDockStorage, as: \.isSidebarApproachingDock) }
        set { publish(newValue, into: \.isSidebarApproachingDockStorage, as: \.isSidebarApproachingDock) }
    }
    @ObservationIgnored private var isSidebarApproachingDockStorage = false
    private(set) var isSidebarSurfaceHovered = false
    private var sidebarMorphRevision = 0
    /// Cancels or awaits the current sidebar transition.
    @ObservationIgnored private(set) var sidebarMorphTask: Task<Void, Never>?
    /// Injectable phase timing for sidebar transitions.
    @ObservationIgnored
    var sidebarMorphWait: SidebarMorphWait = { try await Task.sleep(for: $0) }
    var isWindowFocused: Bool {
        get { observed(\.isWindowFocusedStorage, as: \.isWindowFocused) }
        set { publish(newValue, into: \.isWindowFocusedStorage, as: \.isWindowFocused) }
    }
    @ObservationIgnored private var isWindowFocusedStorage = true
    var sidebarWidthTransaction: BrowserSidebarWidthTransaction
    /// Live widths stay local until the divider drag commits.
    var splitWidthTransaction = BrowserSplitWidthTransaction(
        persistedFractions: [1]
    )
    /// The window owns the lift so its preview can outlive the source surface.
    let splitCardLift = BrowserSplitCardLiftState()
    /// This window's extension side panel, if one is open. Transient by
    /// construction: nothing about it reaches the session, disk or sync.
    let extensionSidePanel = BrowserExtensionSidePanelHost()

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
        self.windowState = windowState
        layoutPersistence = BrowserWindowLayoutPersistence(windowState: windowState)
        self.startupBehavior = startupBehavior
        sidebarWidthTransaction = BrowserSidebarWidthTransaction(
            persistedWidth: persistedSidebarWidth
        )
        _ = addressBinding
        _ = isAddressEditingBinding
        registerForNotices()
    }

    private func registerForNotices() {
        BrowserNoticeCenter.shared.register(chrome) { [weak self] in self?.isWindowFocused == true }
    }
}

// MARK: - Lifecycle

extension BrowserRootModel {
    func prepareBrowser() async {
        windowState?.captureSidebar(
            width: Double(sidebarWidth),
            isPresented: chrome.columnVisibility != .detailOnly
        )
        guard !isPrepared, !isPreparingBrowser else { return }
        isPreparingBrowser = true
        defer { isPreparingBrowser = false }

        // Apply the launch choice before yielding to rule-list startup.
        // Once the window accepts input, the user's current selection takes precedence.
        if startupBehavior == .showStartPage {
            browser.presentStartPageForLaunch()
            address = ""
        }
        await pages.prepareContentBlocking()
        isPrepared = true
        synchronizeSelection()
    }

    func reconcilePages() {
        pages.reconcile(session: browser.session)
    }

    func hostWindowFocusChanged(_ isFocused: Bool) {
        // Window scenes route native key-window notifications directly. A new
        // root's initial SwiftUI focus value must not claim a shared page.
        guard !pages.publishesPageMetadataCentrally else { return }
        pages.setWindowFocused(isFocused)
    }

    func reconcileTabIcons() {
        pages.reconcileTabIcons(in: browser.session)
    }

    func reconcileContentBlocking() {
        guard isPrepared else { return }
        let session = browser.session
        Task { await pages.reconcileContentBlocking(in: session) }
    }

    func reconcileCredentialAccess() {
        pages.reconcileCredentialAccess(in: browser.session)
    }

    func reloadContentBlocking() {
        guard isPrepared else { return }
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
                if isFocused { self.registerForNotices() }
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

    /// Shows the address the page of the tab the window shows reads in the
    /// core, or its tab's, in the address field, unless the person is editing
    /// it, the Space is locked or no page shows that tab; another window's or
    /// Space's page never replaces what the field holds.
    func synchronizePageMetadata() {
        guard !isAddressEditing, !selectedSpaceIsLocked, let page = selectedPage else { return }
        address = (page.live.displayURL ?? browser.selectedTab?.url)?.absoluteString ?? ""
    }

}

// MARK: - Navigation

extension BrowserRootModel {
    /// Distinguishes Space changes from tab changes.
    var selectionSnapshot: BrowserRootSelectionSnapshot {
        BrowserRootSelectionSnapshot(
            tabID: browser.selectedTab?.id,
            spaceID: browser.selectedSpaceID
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

    /// Loads what the person typed, which the core resolves by the Space's
    /// address rules. A native Settings or Getting Started tab has no page:
    /// the core gives it the address first, and selection builds its page and
    /// loads it there.
    func submitAddress() {
        let input = address
        if browser.selectedTab?.isWebPage == false {
            guard browser.navigateSelectedTab(to: input) else { return }
            pages.select(session: browser.presented)
        } else {
            pages.select(session: browser.presented)
            guard pages.navigate(to: input) else { return }
        }
        address = (selectedPage?.live.displayURL ?? browser.selectedTab?.url)?.absoluteString ?? input
        isAddressEditing = false
        AddressFocusAction.resign()
    }

    func synchronizeAfterSelectionChange() {
        guard isPrepared else { return }
        isAddressEditing = false
        AddressFocusAction.resign()
        synchronizeSelection()
    }

    func synchronizeAfterSpaceChange() {
        guard isPrepared else { return }
        isAddressEditing = false
        AddressFocusAction.resign()
        if selectedSpaceIsLocked || !pages.isPresentingSelection(in: browser.presented) {
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
        guard isPrepared else { return }
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
            pages.leavePagePresentation()
        } else {
            pages.select(session: browser.presented)
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
        pages.select(session: browser.presented)
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
            browser.navigateSelectedTab(to: url.absoluteString)
        case .newTab:
            if browser.selectedTab?.isStartPage == true {
                browser.navigateSelectedTab(to: url.absoluteString)
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
        pages.select(session: browser.presented)
        pages.navigate(to: url.absoluteString)
        address = url.absoluteString
        return true
    }
}

// MARK: - Feedback

extension BrowserRootModel {
    func presentNotice(revision: Int, reduceMotion: Bool) {
        guard revision > 0, let notice = chrome.notice else { return }
        withAnimation(
            accessibleAnimation(CrestMotion.feedbackPresentation, reduceMotion)
        ) {
            visibleNotice = notice
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: notice.duration)
            guard let self,
                self.chrome.noticeRevision == revision
            else { return }
            withAnimation(
                self.accessibleAnimation(CrestMotion.dismissal, reduceMotion)
            ) {
                self.visibleNotice = nil
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
    var selectedUtilityDownloads: [DownloadState] {
        guard let profileID = browser.selectedSpace?.profile.id else { return [] }
        return pages.downloadCenter.items(for: profileID)
    }

    var newUtilityDownloads: [DownloadState] {
        guard let profileID = browser.selectedSpace?.profile.id else { return [] }
        return pages.downloadCenter.unacknowledgedItems(for: profileID)
    }
}

extension BrowserRootModel: BrowserStoreFirstObservable {}
