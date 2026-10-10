import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class MobileBrowserRootModel {
    let browser: BrowserStore
    let sidebarInteraction: BrowserSidebarInteractionState
    let pages: MobileBrowserPageStore
    let navigation: MobileBrowserNavigationState
    let spaceAccess: BrowserSpaceAccessController
    let windowState: BrowserWindowStateStore?
    private let layoutPersistence: BrowserWindowLayoutPersistence
    let startupBehavior: StartupBehavior

    var address = ""
    var hasPreparedBrowser = false
    let settings: MobileBrowserSettingsPresentation

    var showsSettings: Bool {
        get { settings.showsSheet }
        set { if !newValue { settings.dismissSheet() } }
    }
    var sidebarWidthTransaction: BrowserSidebarWidthTransaction
    /// Live widths stay local until the divider drag commits.
    var splitWidthTransaction = BrowserSplitWidthTransaction(
        persistedFractions: []
    )

    init(
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        navigation: MobileBrowserNavigationState,
        spaceAccess: BrowserSpaceAccessController,
        windowState: BrowserWindowStateStore?,
        startupBehavior: StartupBehavior,
        persistedSidebarWidth: CGFloat
    ) {
        self.browser = browser
        sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
        self.pages = pages
        self.navigation = navigation
        settings = MobileBrowserSettingsPresentation(
            browser: browser, pages: pages, navigation: navigation, spaceAccess: spaceAccess)
        self.spaceAccess = spaceAccess
        self.windowState = windowState
        layoutPersistence = BrowserWindowLayoutPersistence(windowState: windowState)
        self.startupBehavior = startupBehavior
        sidebarWidthTransaction = BrowserSidebarWidthTransaction(
            persistedWidth: persistedSidebarWidth
        )
    }
}

// MARK: - Lifecycle

extension MobileBrowserRootModel {
    func presentationChanged(to presentation: MobileBrowserPresentation) {
        navigation.adapt(to: presentation)
        settings.adapt(to: presentation)
        guard presentation == .regular else { return }
        windowState?.captureSidebar(
            width: Double(sidebarWidth),
            isPresented: navigation.regularSidebarIsDocked
        )
    }

    func prepareBrowser() async {
        guard !hasPreparedBrowser else { return }
        await pages.prepareContentBlocking()
        hasPreparedBrowser = true
        guard startupBehavior.activatesRestoredTab,
            !navigation.defersPageActivation
        else { return }
        synchronizeSelection()
    }

    /// Releases moved pages and discards archived state for removed tabs.
    func reconcileResidentPages() {
        pages.reconcile()
    }

    func reconcileTabIcons() {
        pages.reconcileTabIcons()
    }

    /// Applies current Space credential preferences to resident pages.
    func reconcileCredentialAccess() {
        pages.reconcileCredentialAccess()
    }

    func reconcileContentBlocking() {
        guard hasPreparedBrowser else { return }
        Task { await pages.reconcileContentBlocking() }
    }

    func reloadContentBlocking() {
        guard hasPreparedBrowser else { return }
        Task { await pages.reloadContentBlocking() }
    }

    func relockProtectedSpaces(_ spaceIDs: Set<UUID>) {
        // The Space itself, not just its ID: relocking has to reach the
        // profile its archived tab state is filed under, and that state
        // outlives the resident pages an ID alone can find.
        for space in browser.spaceModels where spaceIDs.contains(space.id) {
            pages.relockProtectedSpace(space)
        }
    }

    func regularSidebarPresentationChanged(
        _ presentation: BrowserSidebarPresentation
    ) {
        windowState?.captureSidebar(isPresented: presentation.reservesSidebarWidth)
        if !presentation.showsSidebar {
            navigation.utilityPresentation.dismiss()
        }
    }
}

// MARK: - Bindings

extension MobileBrowserRootModel {
    var addressBinding: Binding<String> {
        Binding(
            get: { self.address },
            set: { address in
                guard self.address != address else { return }
                self.address = address
            }
        )
    }
}

// MARK: - Page Synchronization

extension MobileBrowserRootModel {
    /// Shows the address the selected page reads in the core in the address
    /// field, unless the person is editing it or the Space is locked.
    func synchronizePageMetadata(isAddressEditing: Bool) {
        guard !isAddressEditing, !selectedSpaceIsLocked, let page = selectedPage else { return }
        address = (page.live.displayURL ?? browser.shownTab?.address)?.absoluteString ?? ""
    }

}

// MARK: - Navigation

extension MobileBrowserRootModel {
    func selectTab(_ id: UUID) {
        guard let space = browser.shownSpace, !spaceAccess.isLocked(space), let tab = space.tabs.model(id) else {
            return
        }
        if settings.destination(for: tab) == .settings {
            presentSettings(
                matching: BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID))
            return
        }
        browser.selectTab(id)
        pages.select()
        address = browser.shownTab?.url ?? ""
        navigation.selectTab()
    }

    /// Loads what the person typed, which the core resolves by the Space's
    /// address rules. A native Settings or Getting Started tab takes the
    /// address first, so a page can open for it. False when a rule refused it.
    @discardableResult
    func submitAddress() -> Bool {
        let input = address
        browser.navigateSelectedTab(to: input)
        guard pages.selectAndNavigate(to: input) else { return false }
        address = (selectedPage?.live.displayURL ?? browser.shownTab?.address)?.absoluteString ?? input
        navigation.selectTab()
        return true
    }

    func openURL(_ url: URL) {
        browser.openNewTab(url: url)
        pages.select()
        address = url.absoluteString
        navigation.selectTab()
    }

    func beginCompactNewTab() {
        browser.openNewTab()
        pages.select()
        address = ""
        navigation.selectTab()
        if navigation.regularSidebarPresentation == .floating {
            navigation.hideRegularSidebar()
        }
    }

    func showTabViewer() {
        navigation.dismissPageToTabViewer()
    }

    func activateSelectedTab() {
        if routeSelectedSettingsAction() { return }
        pages.select()
        address = browser.shownTab?.url ?? ""
        navigation.selectTab()
    }

    func openSettings() {
        settings.open()
    }

    @discardableResult
    func presentSettings(matching assignment: BrowserTabRuntimeAssignment) -> Bool {
        settings.present(matching: assignment)
    }

    @discardableResult
    func routeSelectedSettingsAction() -> Bool {
        settings.routeSelectedSettingsAction()
    }

    func switchSpace(
        _ direction: BrowserSpaceSwipeDirection,
        reduceMotion: Bool
    ) {
        withAnimation(accessibleAnimation(CrestMotion.navigation, reduceMotion)) {
            guard browser.selectAdjacentSpace(direction) != nil else { return }
            pages.select()
            address = browser.shownTab?.url ?? ""
        }
    }

    func focusStartPageAddress() {
        address = ""
    }

}

// MARK: - Selection

extension MobileBrowserRootModel {
    var selectionSnapshot: MobileBrowserRootSelectionSnapshot {
        MobileBrowserRootSelectionSnapshot(
            sessionRevision: browser.sessionRevision,
            selectedSpaceID: browser.selectedSpaceID,
            selectedProfileID: browser.shownSpace?.profileID,
            assignment: browser.shownTabAssignment
        )
    }

    func lockSnapshot(
        presentation: MobileBrowserPresentation
    ) -> MobileBrowserRootLockSnapshot {
        MobileBrowserRootLockSnapshot(
            sessionRevision: browser.sessionRevision,
            selectedSpaceID: browser.selectedSpaceID,
            selectedProfileID: browser.shownSpace?.profileID,
            isLocked: selectedSpaceIsLocked,
            presentation: presentation
        )
    }

    var selectedPageActions: MobileSelectedPageActionPort? {
        MobileSelectedPageActionPort(browser: browser, pages: pages, spaceAccess: spaceAccess)
    }

    var selectedPage: MobileBrowserPage? {
        selectedPageActions?.activePage
    }

    var selectedSpaceIsLocked: Bool {
        guard let space = browser.shownSpace else { return false }
        return spaceAccess.isLocked(space)
    }

    var lockedSpaceIDs: Set<UUID> {
        Set(browser.spaceModels.filter(spaceAccess.isLocked).map(\.id))
    }

    @discardableResult
    func synchronizeSelection(
        from previous: MobileBrowserRootSelectionSnapshot,
        to current: MobileBrowserRootSelectionSnapshot
    ) -> Bool {
        let change = MobileBrowserRootSelectionChange.resolve(
            from: previous,
            to: current
        )
        guard change != .unchanged, hasPreparedBrowser else { return false }
        guard !navigation.defersPageActivation else { return true }
        synchronizeSelection()
        return true
    }

    func synchronizeLockTransition(
        from previous: MobileBrowserRootLockSnapshot,
        to current: MobileBrowserRootLockSnapshot
    ) {
        if current.isLocked {
            navigation.prepareForLockedSpace()
            pages.deactivatePagePresentation()
            address = ""
            return
        }
        guard previous.isLocked, hasPreparedBrowser else { return }
        switch navigation.finishLockedSpaceTransition() {
        case .tabViewer:
            navigation.prepareForSpaceSwitch()
            pages.deactivatePagePresentation()
            address = browser.shownTab?.url ?? ""
        case .selectedPage:
            activateSelectedTab()
        }
    }

    func synchronizeSelection() {
        browser.consumeMovedTabActivation()
        guard !selectedSpaceIsLocked else {
            pages.deactivatePagePresentation()
            address = ""
            return
        }
        pages.select()
        address = browser.shownTab?.url ?? ""
    }
}

// MARK: - Sidebar

extension MobileBrowserRootModel {
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

    func revealSidebarForUtilityCommand(
        presentation: MobileBrowserPresentation
    ) {
        switch presentation {
        case .compact:
            navigation.showTabViewer()
        case .regular:
            navigation.showRegularSidebar()
        }
    }

    func hideRegularSidebar(reduceMotion: Bool) {
        navigation.utilityPresentation.dismiss()
        withAnimation(accessibleAnimation(CrestMotion.chrome, reduceMotion)) {
            navigation.hideRegularSidebar()
        }
    }

    func showRegularSidebar(reduceMotion: Bool) {
        withAnimation(accessibleAnimation(CrestMotion.chrome, reduceMotion)) {
            navigation.showRegularSidebar()
        }
    }

    func toggleSidebar(
        presentation: MobileBrowserPresentation,
        reduceMotion: Bool
    ) {
        if presentation == .compact {
            let revealsPage =
                navigation.compactSidebarPresentation == .docked
            if revealsPage {
                pages.select()
                address = browser.shownTab?.url ?? ""
            }
            withAnimation(accessibleAnimation(CrestMotion.chrome, reduceMotion)) {
                navigation.toggleCompactSidebar()
            }
            return
        }

        if navigation.regularSidebarIsPresented {
            navigation.utilityPresentation.dismiss()
        }
        withAnimation(accessibleAnimation(CrestMotion.chrome, reduceMotion)) {
            navigation.toggleRegularSidebar()
        }
    }

}

// MARK: - Split Layout

extension MobileBrowserRootModel {
    /// The cards the content area presents, as the window's read model
    /// publishes them, so SwiftUI observes what changes when membership does.
    var presentedSplitMembers: [TabStateModel] {
        browser.shownCards
    }

    /// The group the presented cards belong to, or `nil` when one tab presents
    /// alone. Column fractions are stored per group, so a lone tab has no layout
    /// to store.
    var presentedSplitGroupID: UUID? {
        browser.shownSpace.flatMap(browser.shownSplitGroupID(in:))
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

    func focusSplitCard(_ tabID: UUID) {
        guard tabID != browser.shownTab?.id,
            let member = presentedSplitMembers.first(where: { $0.id == tabID }),
            let space = browser.shownSpace, !spaceAccess.isLocked(space)
        else { return }
        if settings.destination(for: member) == .settings {
            presentSettings(
                matching: BrowserTabRuntimeAssignment(tabID: tabID, spaceID: space.id, profileID: space.profileID))
            return
        }
        browser.selectTab(tabID)
        pages.select()
        address = browser.shownTab?.url ?? ""
    }

    /// Builds a page for every column of an iPad split.
    ///
    /// Columns are all visible at once, so all of them load — the lazy,
    /// focused-±1 residency the phone's carousel gets is a property of showing
    /// one card at a time, not of the platform.
    func prepareSplitCardPages() {
        for member in presentedSplitMembers {
            pages.prepareResidentPage(for: member.id)
        }
    }

    /// The toolbar swipe's card move: one step along the presented run, clamped.
    ///
    /// No animation is started here. The carousel owns the motion — it watches
    /// the selection and animates its scroll position with the same
    /// `CrestMotion.spaceSwipe` token the Space pager settles on — so animating
    /// the commit as well would run two curves against one another.
    @discardableResult
    func selectAdjacentSplitCard(
        _ direction: BrowserSpaceSwipeDirection
    ) -> UUID? {
        guard let selectedTabID = browser.shownTab?.id, presentedSplitGroupID != nil,
            let target = MobileSplitCardPagerPolicy.adjacentMember(
                of: selectedTabID, in: presentedSplitMembers.map(\.id), direction: direction)
        else { return nil }
        browser.selectTab(target)
        pages.select()
        address = browser.shownTab?.url ?? ""
        return target
    }
}

// MARK: - Command Palette

extension MobileBrowserRootModel {
    var selectedTabAssignment: BrowserTabRuntimeAssignment? {
        browser.shownTabAssignment
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
        if settings.destination(for: destination.tab) == .settings {
            browser.selectSpace(destination.space.id)
            return presentSettings(matching: target)
        }
        browser.selectSpace(destination.space.id)
        browser.selectTab(destination.tab.id)
        pages.select()
        address = browser.shownTab?.url ?? ""
        return true
    }

    /// Opens `url` from the palette where `opening` says, from `source`, once
    /// the source's Space may still act.
    @discardableResult
    func openPaletteURL(
        _ url: URL,
        mode: BrowserCommandPaletteMode,
        from source: BrowserTabRuntimeAssignment,
        opening: BrowserCommandPaletteOpening = .here
    ) -> Bool {
        guard
            BrowserCommandPaletteActionPolicy.isSourceAvailable(
                source,
                in: browser,
                accessController: spaceAccess
            )
        else { return false }
        return opening.open(url, from: source, with: MobilePaletteOpener(model: self, mode: mode))
    }

    /// Loads `url` in the page the window shows and shows it in the address field.
    fileprivate func showLoading(_ url: URL) {
        pages.selectAndNavigate(to: url.absoluteString)
        address = url.absoluteString
    }
}

/// How an iPhone or iPad window opens an address from its palette: in place
/// of the source tab, or in a new tab when the palette opened for one, or in
/// a new tab behind or in front. Neither Split View nor a Quick Window opens
/// from the palette here.
@MainActor
private struct MobilePaletteOpener: BrowserCommandPaletteOpener {
    let model: MobileBrowserRootModel
    let mode: BrowserCommandPaletteMode

    func openHere(_ url: URL, from source: BrowserTabRuntimeAssignment) -> Bool {
        if mode == .newTab { return openTab(url, from: source, selecting: true) }
        model.browser.navigateSelectedTab(to: url.absoluteString)
        model.showLoading(url)
        return true
    }

    func openTab(_ url: URL, from source: BrowserTabRuntimeAssignment, selecting: Bool) -> Bool {
        guard selecting else { return model.browser.openNewTab(url: url, in: source.spaceID, selecting: false) != nil }
        guard model.browser.openAddress(url, in: source.spaceID) else { return false }
        model.showLoading(url)
        return true
    }

    func openInSplit(_ url: URL, from source: BrowserTabRuntimeAssignment) -> Bool { false }

    func openInQuickWindow(_ url: URL, from source: BrowserTabRuntimeAssignment) -> Bool { false }
}

// MARK: - Animation

extension MobileBrowserRootModel {
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

extension MobileBrowserRootModel {
    var selectedUtilityDownloads: [DownloadState] {
        guard let profileID = browser.shownSpace?.profileID else { return [] }
        return pages.downloadCenter.items(for: profileID)
    }

    var newUtilityDownloads: [DownloadState] {
        guard let profileID = browser.shownSpace?.profileID else { return [] }
        return pages.downloadCenter.unacknowledgedItems(for: profileID)
    }
}
