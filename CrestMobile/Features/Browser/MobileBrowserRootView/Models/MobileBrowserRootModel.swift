import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class MobileBrowserRootModel {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let navigation: MobileBrowserNavigationState
    let spaceAccess: BrowserSpaceAccessController
    let windowState: BrowserWindowStateStore?
    let startupBehavior: BrowserStartupBehavior

    var address = ""
    var hasPreparedBrowser = false
    var sidebarWidthTransaction: BrowserSidebarWidthTransaction
    /// Live column fractions for the presented split, seeded from this window's
    /// stored layout whenever membership changes. Pointer-rate resizing lives in
    /// the transaction so a divider drag is not a persistence event per frame.
    var splitWidthTransaction = BrowserSplitWidthTransaction(
        persistedFractions: []
    )

    init(
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        navigation: MobileBrowserNavigationState,
        spaceAccess: BrowserSpaceAccessController,
        windowState: BrowserWindowStateStore?,
        startupBehavior: BrowserStartupBehavior,
        persistedSidebarWidth: CGFloat
    ) {
        self.browser = browser
        self.pages = pages
        self.navigation = navigation
        self.spaceAccess = spaceAccess
        self.windowState = windowState
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
        guard presentation == .regular else { return }
        windowState?.captureSidebar(
            width: Double(sidebarWidth),
            isPresented: navigation.regularSidebarIsPresented
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

    /// Brings resident pages back in line with the tabs the session still has,
    /// releasing pages whose tab moved to another Space or profile and dropping
    /// the archived state of tabs that are gone for good.
    func reconcileResidentPages() {
        pages.reconcile(session: browser.session)
    }

    func reconcileTabIcons() {
        pages.reconcileTabIcons(in: browser.session)
    }

    /// Carries each Space's "save passwords" preference into the running pages, so
    /// turning it off takes effect on the surface the user is looking at rather
    /// than only on the next page they open.
    func reconcileCredentialAccess() {
        pages.reconcileCredentialAccess(in: browser.session)
    }

    func reconcileContentBlocking() {
        guard hasPreparedBrowser else { return }
        let session = browser.session
        Task { await pages.reconcileContentBlocking(in: session) }
    }

    func reloadContentBlocking() {
        guard hasPreparedBrowser else { return }
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

    func recordRenderedSelection(_ selection: BrowserTabRuntimeAssignment?) {
        guard let selection else { return }
        windowState?.recordRenderedTab(
            selection.tabID,
            in: selection.spaceID,
            session: browser.session
        )
    }

    func regularSidebarPresentationChanged(_ isPresented: Bool) {
        windowState?.captureSidebar(isPresented: isPresented)
        if !isPresented {
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
    func synchronizePageMetadata(isAddressEditing: Bool) {
        guard let page = selectedPage else { return }
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

    func recordCompletedNavigation(isAddressEditing: Bool) {
        guard let page = selectedPage,
            let url = page.url
        else { return }
        synchronizePageMetadata(isAddressEditing: isAddressEditing)
        browser.recordVisit(url: url, title: page.title)
        guard let space = browser.selectedSpace else { return }
        Task { await pages.styleVisitedLinks(in: space) }
    }
}

// MARK: - Navigation

extension MobileBrowserRootModel {
    func selectTab(_ id: TabID) {
        browser.selectTab(id)
        pages.select(session: browser.session)
        address = browser.selectedTab?.url?.absoluteString ?? ""
        navigation.selectTab()
    }

    @discardableResult
    func submitAddress() -> Bool {
        guard
            let url = AddressResolver.resolve(
                address,
                searchProvider: browser.selectedSpace?.browsingPreferences.searchProvider
                    ?? .google
            )
        else { return false }
        browser.navigateSelectedTab(to: url)
        pages.select(session: browser.session)
        pages.load(url)
        address = url.absoluteString
        navigation.selectTab()
        return true
    }

    func openURL(_ url: URL) {
        browser.openNewTab(url: url)
        pages.select(session: browser.session)
        address = url.absoluteString
        navigation.selectTab()
    }

    func beginCompactNewTab() {
        browser.openNewTab()
        pages.select(session: browser.session)
        address = ""
        navigation.selectTab()
    }

    func showTabViewer() {
        navigation.dismissPageToTabViewer()
    }

    func activateSelectedTab() {
        pages.select(session: browser.session)
        address = browser.selectedTab?.url?.absoluteString ?? ""
        navigation.selectTab()
    }

    func switchSpace(
        _ direction: BrowserSpaceSwipeDirection,
        reduceMotion: Bool
    ) {
        withAnimation(accessibleAnimation(CrestMotion.navigation, reduceMotion)) {
            guard browser.selectAdjacentSpace(direction) != nil else { return }
            pages.select(session: browser.session)
            address = browser.selectedTab?.url?.absoluteString ?? ""
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
            selectedSpaceID: browser.session.selectedSpaceID,
            selectedProfileID: browser.selectedSpace?.profile.id,
            assignment: browser.selectedSpace.flatMap { space in
                browser.selectedTab.map { tab in
                    BrowserTabRuntimeAssignment(
                        tabID: tab.id,
                        spaceID: space.id,
                        profileID: space.profile.id
                    )
                }
            }
        )
    }

    func lockSnapshot(
        presentation: MobileBrowserPresentation
    ) -> MobileBrowserRootLockSnapshot {
        MobileBrowserRootLockSnapshot(
            sessionRevision: browser.sessionRevision,
            selectedSpaceID: browser.session.selectedSpaceID,
            selectedProfileID: browser.selectedSpace?.profile.id,
            isLocked: selectedSpaceIsLocked,
            presentation: presentation
        )
    }

    var selectedPageActions: MobileSelectedPageActionPort? {
        MobileSelectedPageActionPort(browser: browser, pages: pages)
    }

    var selectedPage: MobileBrowserPage? {
        selectedPageActions?.activePage
    }

    var renderedPageSelection: BrowserTabRuntimeAssignment? {
        guard let page = selectedPage else { return nil }
        return BrowserTabRuntimeAssignment(
            tabID: page.tabID,
            spaceID: page.spaceID,
            profileID: page.profileID
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
            navigation.prepareForSpaceSwitch()
            pages.deactivatePagePresentation()
            address = ""
            return
        }
        guard previous.isLocked, hasPreparedBrowser else { return }
        switch MobileBrowserSpaceSwitchPolicy.destinationAfterLeavingLockedSpace(
            in: current.presentation
        ) {
        case .tabViewer:
            navigation.prepareForSpaceSwitch()
            pages.deactivatePagePresentation()
            address = browser.selectedTab?.url?.absoluteString ?? ""
        case .selectedPage:
            activateSelectedTab()
        }
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
            if navigation.compactShowsPage {
                navigation.showTabViewer()
            } else {
                activateSelectedTab()
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
    /// The cards the content area presents for the current selection.
    ///
    /// Derived from the session rather than read out of
    /// `MobileBrowserPageStore.presentedTabIDs`: both answer the same
    /// `presentedSplitMembers(for:)` question, and taking the session's answer is
    /// what keeps SwiftUI observing the thing that actually changes when
    /// membership does.
    var presentedSplitMembers: [BrowserTab] {
        guard let space = browser.selectedSpace else { return [] }
        return space.presentedSplitMembers(for: browser.selectedTab?.id)
    }

    /// The group the presented cards belong to, or `nil` when one tab presents
    /// alone. Column fractions are stored per group, so a lone tab has no layout
    /// to store.
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
        pages.select(session: browser.session)
        address = browser.selectedTab?.url?.absoluteString ?? ""
    }

    /// Builds a page for every column of an iPad split.
    ///
    /// Columns are all visible at once, so all of them load — the lazy,
    /// focused-±1 residency the phone's carousel gets is a property of showing
    /// one card at a time, not of the platform.
    func prepareSplitCardPages() {
        for member in presentedSplitMembers {
            pages.prepareResidentPage(for: member.id, in: browser.session)
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
    ) -> TabID? {
        guard let selectedTabID = browser.selectedTab?.id,
            let space = browser.selectedSpace,
            space.splitGroup(containing: selectedTabID) != nil,
            let target = MobileSplitCardPagerPolicy.adjacentMember(
                of: selectedTabID,
                in: space.presentedSplitMembers(for: selectedTabID).map(\.id),
                direction: direction
            )
        else { return nil }
        browser.selectTab(target)
        pages.select(session: browser.session)
        address = browser.selectedTab?.url?.absoluteString ?? ""
        return target
    }
}

// MARK: - Command Palette

extension MobileBrowserRootModel {
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
    var selectedUtilityDownloads: [BrowserDownloadItem] {
        guard let profileID = browser.selectedSpace?.profile.id else { return [] }
        return pages.downloadCenter.items(for: profileID)
    }

    var newUtilityDownloads: [BrowserDownloadItem] {
        guard let profileID = browser.selectedSpace?.profile.id else { return [] }
        return pages.downloadCenter.unacknowledgedItems(for: profileID)
    }
}
