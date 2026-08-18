import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class BrowserRootModel {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let chrome: BrowserChromeState
    let spaceAccess: BrowserSpaceAccessController
    let windowState: BrowserWindowStateStore?
    let startupBehavior: BrowserStartupBehavior

    var address = ""
    var isAddressEditing = false
    var hasRestoredExtensions = false
    var isURLCopiedFeedbackVisible = false
    var visiblePageZoomFeedbackLabel: String?
    var isFloatingSidebarPresented = false
    private(set) var isSidebarMorphing = false
    private(set) var isSidebarSurfaceHovered = false
    private var sidebarMorphRevision = 0
    @ObservationIgnored private var sidebarMorphTask: Task<Void, Never>?
    var isWindowFocused = true
    var sidebarWidthTransaction: BrowserSidebarWidthTransaction
    /// Pointer-rate column widths for the presented split, seeded from this
    /// window's stored layout and committed back to it once per drag. A window
    /// presenting a single tab holds the one-column identity rather than a
    /// separate "no split" state.
    var splitWidthTransaction = BrowserSplitWidthTransaction(
        persistedFractions: [1]
    )
    /// The card this window is carrying on the pointer, if any.
    ///
    /// Per window rather than per surface, because the shell has to reach it
    /// too: the preview travels in a window ordered above this one, and that is
    /// seated at the root rather than inside the content area it left.
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
        self.pages = pages
        self.chrome = chrome
        self.spaceAccess = spaceAccess
        self.windowState = windowState
        self.startupBehavior = startupBehavior
        sidebarWidthTransaction = BrowserSidebarWidthTransaction(
            persistedWidth: persistedSidebarWidth
        )
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
        address = browser.selectedTab?.url?.absoluteString ?? ""
        if startupBehavior.activatesRestoredTab {
            synchronizeSelection()
        }
    }

    func reconcileExtensions() {
        pages.reconcile(session: browser.session)
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
    /// Native text controls may write their current value while reconciling.
    /// Deduplicating that write keeps Observation from invalidating the entire
    /// sidebar for a value that did not actually change.
    var addressBinding: Binding<String> {
        Binding(
            get: { self.address },
            set: { address in
                guard self.address != address else { return }
                self.address = address
            }
        )
    }

    var isAddressEditingBinding: Binding<Bool> {
        Binding(
            get: { self.isAddressEditing },
            set: { isEditing in
                guard self.isAddressEditing != isEditing else { return }
                self.isAddressEditing = isEditing
            }
        )
    }

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
    func synchronizePageMetadata() {
        guard let page = pages.activePage else { return }
        browser.updateSelectedTabFromPage(
            url: page.displayURL,
            title: page.navigationFailure?.displayHost ?? page.title,
            faviconData: page.faviconData,
            iconAccent: page.siteThemeIconAccent
        )
        if !isAddressEditing {
            address =
                (page.displayURL ?? browser.selectedTab?.url)?.absoluteString
                ?? ""
        }
    }

    func recordCompletedNavigation() {
        guard let page = pages.activePage, let url = page.url else { return }
        synchronizePageMetadata()
        browser.recordVisit(url: url, title: page.title)
        guard let space = browser.selectedSpace else { return }
        Task { await pages.styleVisitedLinks(in: space) }
    }
}

// MARK: - Navigation

extension BrowserRootModel {
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
        guard hasRestoredExtensions else { return }
        isAddressEditing = false
        AddressFocusAction.resign()
        synchronizeSelection()
    }

    func synchronizeAfterSpaceChange() {
        guard hasRestoredExtensions else { return }
        isAddressEditing = false
        AddressFocusAction.resign()
        guard BrowserSpaceContentSelectionPolicy.rootObserverDefersSpaceChanges else {
            synchronizeSelection()
            return
        }
        address = browser.selectedTab?.url?.absoluteString ?? ""
    }

    func synchronizeAfterLockChange() {
        guard hasRestoredExtensions else { return }
        synchronizeSelection()
    }

    func synchronizeSelection() {
        guard !selectedSpaceIsLocked else {
            pages.deactivatePagePresentation()
            address = ""
            return
        }
        pages.select(session: browser.session)
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
        pages.select(session: browser.session)
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
        guard windowState == nil else { return }
        guard width != sidebarWidthTransaction.persistedWidth else { return }
        sidebarWidthTransaction.restore(persistedWidth: width)
    }

    func commitSidebarWidth(_ width: CGFloat) -> CGFloat? {
        sidebarWidthTransaction.resize(to: width)
        guard let committedWidth = sidebarWidthTransaction.commit() else {
            return nil
        }
        if let windowState {
            windowState.captureSidebar(width: Double(committedWidth))
            return nil
        }
        return committedWidth
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
            try? await Task.sleep(
                for: CrestMotion.sidebarMorphCompletionDelay
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
                        CrestMotion.sidebarMorph,
                        reduceMotion
                    )
                ) {
                    self.isFloatingSidebarPresented = false
                    self.chrome.showSidebar()
                }
                try? await Task.sleep(
                    for: CrestMotion.sidebarMorphCompletionDelay
                )
                guard !Task.isCancelled else { return }
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

    /// Adopts the layout this window last stored for the presented group.
    ///
    /// Called whenever the presented membership changes — a different group, a
    /// member joining or leaving, members reordering — because fractions are
    /// positional and a list written for one arrangement means nothing under
    /// another. A group this window has never resized starts as equal columns.
    func seedSplitColumnFractions() {
        let members = presentedSplitMembers
        guard !members.isEmpty else { return }
        let persisted = presentedSplitGroupID.flatMap { groupID in
            windowState?.splitColumnFractions(for: groupID)
        }
        splitWidthTransaction.begin(
            fractions: BrowserSplitLayoutSeedPolicy.fractions(
                persisted: persisted,
                memberCount: members.count
            )
        )
    }

    /// Records what a completed divider drag settled on. Column widths are a
    /// per-window, device-local preference and never reach the session or sync.
    func commitSplitColumnFractions(_ fractions: [Double]) {
        guard let windowState, let groupID = presentedSplitGroupID else { return }
        windowState.captureSplitLayout(fractions: fractions, for: groupID)
    }

    /// Makes one presented card the focused card.
    ///
    /// Focus *is* selection, so this is an ordinary selection change: the
    /// existing selection observer re-presents the group with the new focus and
    /// every chrome surface follows without a second focus state anywhere.
    func focusSplitCard(_ tabID: TabID) {
        guard tabID != browser.selectedTab?.id,
            presentedSplitMembers.contains(where: { $0.id == tabID })
        else { return }
        browser.selectTab(tabID)
    }
}

// MARK: - Command Palette

extension BrowserRootModel {
    /// The Spaces the launcher may search besides the one on screen. Deleting
    /// Spaces are excluded because selecting one would resurrect it.
    var paletteOtherSpaces: [BrowserSpace] {
        guard let source = paletteSourceAssignment else { return [] }
        return BrowserCommandPaletteActionPolicy.availableOtherSpaces(
            from: source,
            in: browser,
            accessController: spaceAccess
        )
    }

    var paletteSourceAssignment: BrowserTabRuntimeAssignment? {
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
