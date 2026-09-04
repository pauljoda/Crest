import AppKit
import SwiftUI

/// Every command Crest's Mac shell can run, as ordinary methods on a value.
///
/// The menu bar used to own these bodies privately, which meant the command
/// palette could only have reached them by copying them. Naming them here — the
/// same shape `MobileBrowserCommandController` already has on iOS — lets the
/// menu bar and the launcher run one implementation.
@MainActor
struct BrowserCommandActions {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let chrome: BrowserChromeState
    let openWindow: OpenWindowAction
    /// The window a Quick Window should hand its result back to, when the
    /// command was issued from a focused browser window.
    var targetWindowID: BrowserWindowID?
    /// Which way the cards are laid out, for the commands that name a side of
    /// the screen. Only the split-card moves read it; see
    /// `BrowserSplitCardMoveDirection`.
    var layoutDirection: LayoutDirection = .leftToRight
    var extensionSidebar: BrowserExtensionSidebarHost? = nil

    /// The commands the launcher offers on macOS.
    ///
    /// Numbered tab and Space selection are left out: they are chords, not
    /// things anyone searches for by name, and the launcher already lists the
    /// tabs themselves.
    static let paletteCommands: [BrowserShortcutCommand] = [
        .newWindow,
        .newQuickWindow,
        .newPrivateWindow,
        .closeTabOrWindow,
        .closeWindow,
        .back,
        .forward,
        .reloadPage,
        .stopLoading,
        .reloadFromOrigin,
        .toggleSelectedTabPinned,
        .duplicateTab,
        .reopenClosedTab,
        .clearUnpinnedTabs,
        .archiveTab,
        .previousTab,
        .nextTab,
        .mostRecentTab,
        .splitWithNextTab,
        .focusNextSplitCard,
        .focusPreviousSplitCard,
        .removeTabFromSplit,
        .separateSplitTabs,
        .moveSplitCardLeft,
        .moveSplitCardRight,
        .previousSpace,
        .nextSpace,
        .toggleReaderMode,
        .toggleContentBlocking,
        .findInPage,
        .zoomIn,
        .zoomOut,
        .actualSize,
        .copyPageLink,
        .copyPageLinkAsMarkdown,
        .sharePage,
        .exportPDF,
        .saveWebArchive,
        .printPage,
        .toggleSidebar,
        .toggleExtensionSidePanel,
        .showHistory,
        .showArchive,
        .showDownloads,
        .showWebInspector,
    ]

    func paletteRegistry(
        shortcuts: BrowserShortcutStore?
    ) -> BrowserCommandPaletteCommandRegistry {
        BrowserCommandPaletteCommandRegistry(
            commands: Self.paletteCommands,
            shortcut: { shortcuts?.shortcut(for: $0) },
            perform: perform
        )
    }

    func perform(_ command: BrowserShortcutCommand) {
        switch command {
        case .newWindow: openNewWindow()
        case .newTab: openNewTab()
        case .openLocation: openLocation()
        case .newQuickWindow: openQuickWindow()
        case .newPrivateWindow: openPrivateWindow()
        case .closeTabOrWindow: closeTabOrWindow()
        case .closeWindow: closeKeyWindow()
        case .back: pages.goBack()
        case .forward: pages.goForward()
        case .reloadPage: pages.reloadOrStop(in: browser.session)
        case .stopLoading: pages.stopLoading()
        case .reloadFromOrigin: pages.reloadFromOrigin(in: browser.session)
        case .toggleSelectedTabPinned: toggleSelectedTabPinned()
        case .duplicateTab: duplicateSelectedTab()
        case .reopenClosedTab: reopenClosedTab()
        case .clearUnpinnedTabs: cleanupCurrentTabs()
        case .archiveTab: archiveSelectedTab()
        case .previousTab: selectPreviousTab()
        case .nextTab: selectNextTab()
        case .mostRecentTab: selectMostRecentTab()
        case .splitWithNextTab: splitWithNextTab()
        case .focusNextSplitCard: focusAdjacentSplitCard(offset: 1)
        case .focusPreviousSplitCard: focusAdjacentSplitCard(offset: -1)
        case .removeTabFromSplit: removeSelectedTabFromSplit()
        case .separateSplitTabs: separateSplitTabs()
        case .moveSplitCardLeft: moveFocusedSplitCard(.left)
        case .moveSplitCardRight: moveFocusedSplitCard(.right)
        case .previousSpace: selectPreviousSpace()
        case .nextSpace: selectNextSpace()
        case .toggleReaderMode: pages.toggleReaderMode()
        case .toggleContentBlocking: toggleContentBlocking()
        case .findInPage: pages.presentFind()
        case .zoomIn: zoomIn()
        case .zoomOut: zoomOut()
        case .actualSize: resetZoom()
        case .copyPageLink: copyPageLink()
        case .copyPageLinkAsMarkdown: copyPageLinkAsMarkdown()
        case .sharePage: pages.sharePage()
        case .exportPDF: pages.exportPDF()
        case .saveWebArchive: pages.exportWebArchive()
        case .printPage: pages.printPage()
        case .toggleSidebar: toggleSidebar()
        case .toggleExtensionSidePanel: extensionSidebar?.toggle()
        case .showHistory: chrome.presentHistory()
        case .showArchive: presentArchive()
        case .showDownloads: presentDownloads()
        case .showWebInspector: pages.showWebInspector()
        case .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9:
            selectTab(at: numberedIndex(of: command, in: BrowserShortcutCommand.tabSelection))
        case .selectSpace1, .selectSpace2, .selectSpace3, .selectSpace4,
            .selectSpace5, .selectSpace6, .selectSpace7, .selectSpace8,
            .selectSpace9:
            selectSpace(at: numberedIndex(of: command, in: BrowserShortcutCommand.spaceSelection))
        }
    }

    private func numberedIndex(
        of command: BrowserShortcutCommand,
        in resolve: (Int) -> BrowserShortcutCommand?
    ) -> Int {
        (1...9).first { resolve($0) == command }.map { $0 - 1 } ?? 0
    }

    // MARK: - Windows

    func openNewTab() {
        chrome.openNewTab(
            isStartPageSelected: browser.selectedTab?.isStartPage == true
        )
    }

    func openNewWindow() {
        openWindow(id: BrowserSceneID.browser.rawValue)
    }

    func openPrivateWindow() {
        openWindow(id: BrowserSceneID.privateBrowser.rawValue)
    }

    func openQuickWindow() {
        guard let space = browser.selectedSpace else { return }
        openWindow(
            id: BrowserSceneID.quickWindow.rawValue,
            value: BrowserQuickWindowRequest.empty(
                spaceAssignment: BrowserSpaceRuntimeAssignment(space: space),
                targetWindowID: targetWindowID
            )
        )
    }

    func closeKeyWindow() {
        NSApp.keyWindow?.performClose(nil)
    }

    func closeTabOrWindow() {
        guard let selectedTab = browser.selectedTab else {
            closeKeyWindow()
            return
        }

        switch BrowserTabDismissalPolicy.action(
            for: selectedTab,
            tabCount: orderedTabs.count
        ) {
        case .closeTab:
            if selectedTab.isStartPage {
                browser.closeTab(selectedTab.id)
                pages.reconcile(session: browser.session)
                pages.select(session: browser.session)
            } else {
                archiveSelectedTab()
            }
        case .unloadPage:
            browser.selectDismissalFallback(afterDismissing: selectedTab.id)
            pages.unloadPage(for: selectedTab.id)
            pages.select(session: browser.session)
        case .closeWindow:
            closeKeyWindow()
        }
    }

    // MARK: - Conditions

    var orderedTabs: [BrowserTab] {
        browser.selectedSpace?.tabs ?? []
    }

    var canArchiveSelectedTab: Bool {
        browser.selectedTab?.placement == .current
            && browser.selectedTab?.isStartPage == false
    }

    var canDuplicateSelectedTab: Bool {
        browser.selectedTab?.isStartPage == false
    }

    var canReloadSelectedTab: Bool {
        browser.selectedTab?.url != nil
    }

    var contentBlockingActionTitle: LocalizedStringResource {
        switch browser.selectedSpace?.browsingPreferences.contentBlockingPolicy {
        case .balanced:
            "Turn Off Content Blocking in This Space"
        case .off, nil:
            "Turn On Balanced Content Blocking in This Space"
        }
    }

    // MARK: - Chrome

    func presentArchive() {
        chrome.showSidebar()
        chrome.utilityPresentation.present(.archive)
    }

    func presentDownloads() {
        chrome.showSidebar()
        chrome.utilityPresentation.present(.downloads)
    }

    func toggleSidebar() {
        if chrome.columnVisibility == .detailOnly {
            chrome.showSidebar()
        } else {
            chrome.hideSidebar()
        }
    }

    func openLocation() {
        chrome.openLocation(browser.selectedTab?.url?.absoluteString ?? "")
    }

    // MARK: - Page

    func copyPageLink() {
        guard pages.copyPageLink() else { return }
        chrome.showURLCopiedFeedback()
    }

    func copyPageLinkAsMarkdown() {
        guard pages.copyPageLinkAsMarkdown() else { return }
        chrome.showURLCopiedFeedback()
    }

    func toggleContentBlocking() {
        guard let space = browser.selectedSpace else { return }
        var preferences = space.browsingPreferences
        preferences.contentBlockingPolicy =
            preferences.contentBlockingPolicy == .balanced ? .off : .balanced
        browser.updateBrowsingPreferences(preferences, in: space.id)
        let session = browser.session
        Task { await pages.reconcileContentBlocking(in: session) }
    }

    func zoomIn() {
        guard pages.zoomIn() else { return }
        chrome.showPageZoomFeedback(pages.pageZoomLabel)
    }

    func zoomOut() {
        guard pages.zoomOut() else { return }
        chrome.showPageZoomFeedback(pages.pageZoomLabel)
    }

    func resetZoom() {
        guard pages.resetZoom() else { return }
        chrome.showPageZoomFeedback(pages.pageZoomLabel)
    }

    // MARK: - Tabs

    func toggleSelectedTabPinned() {
        guard let tab = browser.selectedTab else { return }
        let destination: TabPlacement = tab.placement == .pinned ? .current : .pinned
        guard browser.moveTab(tab.id, to: destination) else { return }
        pages.select(session: browser.session)
    }

    func duplicateSelectedTab() {
        guard browser.duplicateSelectedTab() != nil else { return }
        pages.reconcile(session: browser.session)
        pages.select(session: browser.session)
    }

    func reopenClosedTab() {
        guard
            let archived = browser.selectedSpace?.archivedTabs.max(
                by: { $0.archivedAt < $1.archivedAt }
            )
        else { return }
        browser.restoreArchivedTab(archived.id)
        browser.selectTab(archived.id)
        pages.select(session: browser.session)
    }

    func cleanupCurrentTabs() {
        browser.cleanupCurrentTabs()
        pages.reconcile(session: browser.session)
        pages.select(session: browser.session)
    }

    func archiveSelectedTab() {
        guard browser.archiveSelectedTab() != nil else { return }
        pages.reconcile(session: browser.session)
        pages.select(session: browser.session)
    }

    func selectPreviousTab() {
        selectTab(offset: -1)
    }

    func selectNextTab() {
        selectTab(offset: 1)
    }

    func selectMostRecentTab() {
        guard let selectedID = browser.selectedTab?.id,
            let recent =
                orderedTabs
                .filter({ $0.id != selectedID })
                .max(by: { $0.lastActivatedAt < $1.lastActivatedAt })
        else { return }
        browser.selectTab(recent.id)
        pages.select(session: browser.session)
    }

    func selectTab(offset: Int) {
        guard browser.selectAdjacentTab(offset: offset) != nil else { return }
        pages.select(session: browser.session)
    }

    func selectTab(at index: Int) {
        guard orderedTabs.indices.contains(index) else { return }
        browser.selectTab(orderedTabs[index].id)
        pages.select(session: browser.session)
    }

    // MARK: - Split View

    /// The cards the content area is presenting right now, focused member
    /// included. One element means the selection is an ordinary tab.
    var presentedSplitMembers: [BrowserTab] {
        guard let space = browser.selectedSpace else { return [] }
        return space.presentedSplitMembers(for: space.selectedTabID)
    }

    var isSelectedTabInSplit: Bool {
        presentedSplitMembers.count > 1
    }

    var canSplitWithNextTab: Bool {
        browser.nextSplitJoinCandidate != nil
    }

    /// Adds the next eligible tab in the selected tab's own section to its
    /// split, creating the group when there is none yet.
    func splitWithNextTab() {
        guard let space = browser.selectedSpace,
            let selectedTabID = space.selectedTabID,
            let candidate = browser.nextSplitJoinCandidate,
            browser.addTabToSplit(
                BrowserTabDragItem(
                    tabID: candidate.id,
                    spaceID: space.id,
                    profileID: space.profile.id
                ),
                joining: selectedTabID,
                at: nil
            )
        else { return }
        pages.select(session: browser.session)
    }

    /// Moves focus one card along the presented run and wraps at both ends.
    ///
    /// Focus is selection, so this is `selectTab` and nothing else: the URL
    /// bar, find bar, and every page command follow the selection pipeline they
    /// already followed before splits existed.
    func focusAdjacentSplitCard(offset: Int) {
        let members = presentedSplitMembers
        guard members.count > 1,
            let selectedTabID = browser.selectedSpace?.selectedTabID,
            let index = members.firstIndex(where: { $0.id == selectedTabID })
        else { return }
        let count = members.count
        let wrappedIndex = (index + offset % count + count) % count
        browser.selectTab(members[wrappedIndex].id)
        pages.select(session: browser.session)
    }

    /// The on-screen direction resolved against this shell's layout, so a menu
    /// item and the palette ask the same question the same way.
    func canMoveFocusedSplitCard(
        _ direction: BrowserSplitCardMoveDirection
    ) -> Bool {
        canMoveFocusedSplitCard(
            offset: direction.memberOffset(layoutDirection: layoutDirection)
        )
    }

    func moveFocusedSplitCard(_ direction: BrowserSplitCardMoveDirection) {
        moveFocusedSplitCard(
            offset: direction.memberOffset(layoutDirection: layoutDirection)
        )
    }

    /// Whether the focused card has anywhere to go `offset` slots along.
    func canMoveFocusedSplitCard(offset: Int) -> Bool {
        guard let space = browser.selectedSpace,
            let selectedTabID = space.selectedTabID
        else { return false }
        return browser.canMoveSplitMember(
            selectedTabID,
            by: offset,
            matching: BrowserSpaceRuntimeAssignment(space: space)
        )
    }

    /// Slides the focused card along its split run.
    ///
    /// No `pages.select(session:)` afterwards, unlike every other split command
    /// here: the selection is the same tab and the same set of cards is on
    /// screen, so there is nothing for the pool to reconcile. The column row
    /// reads member order straight from the session and re-lays itself out.
    func moveFocusedSplitCard(offset: Int) {
        guard let space = browser.selectedSpace,
            let selectedTabID = space.selectedTabID
        else { return }
        browser.moveSplitMember(
            selectedTabID,
            by: offset,
            matching: BrowserSpaceRuntimeAssignment(space: space)
        )
    }

    /// Drops the focused card out of its split and leaves it an ordinary tab.
    func removeSelectedTabFromSplit() {
        guard let space = browser.selectedSpace,
            let selectedTabID = space.selectedTabID,
            browser.removeTabFromSplit(
                selectedTabID,
                matching: BrowserSpaceRuntimeAssignment(space: space)
            )
        else { return }
        pages.select(session: browser.session)
    }

    /// "Separate All Tabs": every card in the presented split becomes a tab.
    func separateSplitTabs() {
        guard let space = browser.selectedSpace,
            let selectedTabID = space.selectedTabID,
            browser.dissolveSplit(
                containing: selectedTabID,
                matching: BrowserSpaceRuntimeAssignment(space: space)
            )
        else { return }
        pages.select(session: browser.session)
    }

    // MARK: - Spaces

    func selectPreviousSpace() {
        selectAdjacentSpace(.previous)
    }

    func selectNextSpace() {
        selectAdjacentSpace(.next)
    }

    func selectAdjacentSpace(_ direction: BrowserSpaceSwipeDirection) {
        guard browser.selectAdjacentSpace(direction) != nil else { return }
        pages.select(session: browser.session)
    }

    func selectSpace(at index: Int) {
        guard browser.session.spaces.indices.contains(index) else { return }
        browser.selectSpace(browser.session.spaces[index].id)
        pages.select(session: browser.session)
    }
}
