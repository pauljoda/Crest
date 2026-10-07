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
    /// The shell's windows, which the window commands open; nil where no
    /// window can open, such as outside a shell window.
    let windows: BrowserMacWindows?
    var spaceAccess = BrowserSpaceAccessController()
    /// The window a Quick Window should hand its result back to, when the
    /// command was issued from a focused browser window.
    var targetWindowID: UUID?
    /// Which way the cards are laid out, for the commands that name a side of
    /// the screen. Only the split-card moves read it; see
    /// `BrowserSplitCardMoveDirection`.
    var layoutDirection: LayoutDirection = .leftToRight

    /// The commands the launcher offers on macOS: every one the core offers
    /// in the palette, in the core's order, since this shell performs each.
    static let paletteCommands = ShortcutCommand.all.filter(\.offersInPalette)

    func paletteRegistry(
        shortcuts: BrowserShortcutStore?
    ) -> BrowserCommandPaletteCommandRegistry {
        BrowserCommandPaletteCommandRegistry(
            commands: Self.paletteCommands.filter { $0.isOffered(in: browser.core.state) },
            shortcut: { shortcuts?.shortcut(for: $0) },
            perform: perform
        )
    }

    func perform(_ command: ShortcutCommand) {
        let route = route(command)
        guard browser.allows(command), route.isAvailable else { return }
        route.run()
    }

    /// Availability belongs to the same command route used by menus and keys:
    /// the core says what the window's contents allow, and the route what the
    /// page and its engine can do. In particular, a disabled split shortcut
    /// must leave text selection alone.
    func canPerform(_ command: ShortcutCommand) -> Bool {
        browser.allows(command) && route(command).isAvailable
    }

    /// What the menu bar calls `command` now, when that follows what the
    /// window shows, such as Reader's Show or Hide; nil for its own title.
    func menuTitle(of command: ShortcutCommand) -> LocalizedStringResource? {
        route(command).title
    }

    /// Whether what `command` shows or hides is showing, for a command the
    /// menu bar checks; nil for any other.
    func isOn(_ command: ShortcutCommand) -> Bool? {
        route(command).isOn
    }

    /// What a command does in the Mac shell, whether it can do it now, and
    /// how the menu bar presents it when that follows the window.
    private struct Route {
        var isAvailable = true
        var title: LocalizedStringResource?
        var isOn: Bool?
        let run: @MainActor () -> Void
    }

    /// The one place that turns each command into what the Mac shell does.
    private func route(_ command: ShortcutCommand) -> Route {
        switch command.kind {
        case .newWindow: Route(run: openNewWindow)
        case .newBlankWindow: Route(run: openBlankWindow)
        case .newTab: Route(run: openNewTab)
        case .openLocation: Route(run: openLocation)
        case .openFile: Route(isAvailable: supportsEngineCapability(.localFiles), run: openFile)
        case .newQuickWindow: Route(run: openQuickWindow)
        case .newPrivateWindow: Route(run: openPrivateWindow)
        case .closeTabOrWindow: Route(run: closeTabOrWindow)
        case .closeWindow: Route(run: closeKeyWindow)
        case .back: Route(isAvailable: pages.canGoBack, run: pages.goBack)
        case .forward: Route(isAvailable: pages.canGoForward, run: pages.goForward)
        case .reloadPage: Route { pages.reloadOrStop() }
        case .stopLoading: Route(isAvailable: pages.isLoading, run: pages.stopLoading)
        case .reloadFromOrigin: Route { pages.reloadFromOrigin() }
        case .toggleSelectedTabPinned: Route(run: toggleSelectedTabPinned)
        case .duplicateTab: Route(run: duplicateSelectedTab)
        case .reopenClosedTab: Route(run: reopenClosedTab)
        case .clearUnpinnedTabs: Route(run: cleanupCurrentTabs)
        case .archiveTab: Route(run: archiveSelectedTab)
        case .previousTab: Route(run: selectPreviousTab)
        case .nextTab: Route(run: selectNextTab)
        case .mostRecentTab: Route(run: selectMostRecentTab)
        case .splitWithNextTab: Route(run: splitWithNextTab)
        case .focusNextSplitCard: Route { focusAdjacentSplitCard(offset: 1) }
        case .focusPreviousSplitCard: Route { focusAdjacentSplitCard(offset: -1) }
        case .removeTabFromSplit: Route(run: removeSelectedTabFromSplit)
        case .separateSplitTabs: Route(run: separateSplitTabs)
        case .moveSplitCardLeft:
            Route(isAvailable: canMoveFocusedSplitCard(.left)) { moveFocusedSplitCard(.left) }
        case .moveSplitCardRight:
            Route(isAvailable: canMoveFocusedSplitCard(.right)) { moveFocusedSplitCard(.right) }
        case .previousSpace: Route(run: selectPreviousSpace)
        case .nextSpace: Route(run: selectNextSpace)
        case .toggleReaderMode:
            Route(
                isAvailable: supportsPageCapability(.reader) && pages.readerModeState.canToggle,
                title: pages.readerModeActionTitle, run: pages.toggleReaderMode)
        case .toggleContentBlocking:
            Route(
                isAvailable: supportsEngineCapability(.contentBlocking), title: contentBlockingActionTitle,
                run: toggleContentBlocking)
        case .findInPage: Route(isAvailable: supportsPageCapability(.find), run: pages.presentFind)
        case .zoomIn: Route(isAvailable: canZoom, run: zoomIn)
        case .zoomOut: Route(isAvailable: canZoom, run: zoomOut)
        case .actualSize: Route(isAvailable: canZoom, run: resetZoom)
        case .copyPageLink: Route(isAvailable: pages.hasActivePage, run: copyPageLink)
        case .copyPageLinkAsMarkdown: Route(isAvailable: pages.hasActivePage, run: copyPageLinkAsMarkdown)
        case .sharePage: Route(isAvailable: pages.hasActivePage, run: pages.sharePage)
        case .exportPDF: Route(isAvailable: supportsPageCapability(.pdf), run: pages.exportPDF)
        case .saveWebArchive: Route(isAvailable: supportsPageCapability(.webArchive), run: pages.exportWebArchive)
        case .printPage: Route(isAvailable: supportsPageCapability(.print), run: pages.printPage)
        case .toggleSidebar: Route(run: toggleSidebar)
        case .showHistory: Route(run: chrome.presentHistory)
        case .showArchive: Route(run: presentArchive)
        case .showDownloads: Route(isAvailable: supportsEngineCapability(.downloads), run: presentDownloads)
        case .showWebInspector:
            Route(isAvailable: supportsPageCapability(.inspector), run: pages.showWebInspector)
        case .toggleTranslationToolbar:
            Route(
                isAvailable: supportsPageCapability(.translation) && !pages.readerModeState.isActive,
                isOn: pages.activePage?.translation.showsToolbar == true
            ) {
                guard let page = pages.activePage, !page.readerModeState.isActive else { return }
                page.translation.toggleToolbarVisibility()
            }
        case .toggleDeveloperToolbar:
            Route(isAvailable: pages.hasActivePage, isOn: pages.activePage?.isDeveloperModeEnabled == true) {
                if let page = pages.activePage {
                    page.setDeveloperToolbarVisible(!page.isDeveloperModeEnabled)
                }
            }
        case .selectNumbered:
            if let selection = numberedSelections[command] {
                switch selection.target.kind {
                case .tab: Route { selectTab(selection.tabID, in: selection.spaceID) }
                case .space: Route { selectSpace(selection.spaceID) }
                }
            } else {
                Route(isAvailable: false) {}
            }
        }
    }

    private var canZoom: Bool {
        supportsPageCapability(.zoom) && pages.activePage?.developerViewport == nil
    }

    private func supportsPageCapability(_ capability: EngineCapability) -> Bool {
        pages.hasActivePage && pages.activePage?.pageEngine.registration.supports(capability) == true
    }

    /// The same question as `supportsPageCapability` for commands that are about
    /// the window rather than the document in it, so they stay available in the
    /// moment before a page exists, when the engine new pages open on answers.
    /// The active page's own engine answers whenever there is one.
    private func supportsEngineCapability(_ capability: EngineCapability) -> Bool {
        pages.activePage?.pageEngine.registration.supports(capability)
            ?? browser.core.state.defaultEngineSupports(capability)
    }

    /// Where each numbered selection command leads right now, per the core.
    var numberedSelections: [ShortcutCommand: NumberedSelection] {
        browser.core.numberedSelections(windowID: browser.windowID)
    }

    // MARK: - Windows

    func openNewTab() {
        chrome.openNewTab(isStartPageSelected: browser.shownTab?.surface == .startPage)
    }

    func openNewWindow() {
        windows?.open(.normal(sourceWindowID: targetWindowID), activation: .key)
    }

    func openBlankWindow() {
        guard !browser.isPrivateBrowsing, let space = browser.shownSpace, !spaceAccess.isLocked(space) else {
            return
        }
        windows?.open(
            .temporary(sourceWindowID: targetWindowID, assignment: BrowserSpaceRuntimeAssignment(space: space)),
            activation: .key)
    }

    func openPrivateWindow() {
        windows?.openPrivateWindow()
    }

    func openQuickWindow() {
        guard let space = browser.shownSpace else { return }
        windows?.openQuickWindow(
            .empty(spaceAssignment: BrowserSpaceRuntimeAssignment(space: space), targetWindowID: targetWindowID))
    }

    func closeKeyWindow() {
        NSApp.keyWindow?.performClose(nil)
    }

    /// Closes the selected tab the way the core closes it, or the window when
    /// the core says only the window is left to close.
    func closeTabOrWindow() {
        guard let selectedTab = browser.shownTab, let space = browser.shownSpace,
            !browser.closingLeavesOnlyTheWindow(selectedTab.id, in: space.id)
        else {
            closeKeyWindow()
            return
        }
        // A saved or pinned tab puts its page away, which the page host
        // follows once the core records it.
        if selectedTab.placement.isDurable {
            if BrowserDurableTabCloseAction(browser: browser, spaceAccess: spaceAccess).perform(
                BrowserTabRuntimeAssignment(
                    tabID: selectedTab.id, spaceID: space.id, profileID: space.profileID
                ))
            {
                pages.select()
            }
        } else if selectedTab.surface == .startPage {
            browser.closeTab(selectedTab.id)
            pages.reconcile()
            pages.select()
        } else {
            archiveSelectedTab()
        }
    }

    // MARK: - Conditions

    var contentBlockingActionTitle: LocalizedStringResource {
        ContentBlockingPolicy.switchTitle(
            for: browser.shownSpace?.settings.browsingPreferences.contentBlocking)
    }

    /// The engines the shown page can move to: every registered engine but
    /// its own, so the choice is there before any page opens on the others.
    var pageEngineMoves: [EngineKind] {
        pages.activePage?.corePage.otherEngines ?? []
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
        chrome.openLocation(browser.shownTab?.url ?? "")
    }

    /// Opens local documents as ordinary tabs in the Space on screen.
    ///
    /// The archive entry follows the active page's engine, not the platform: a
    /// panel offering a `.webarchive` to Chromium would be offering a document
    /// the engine cannot read.
    func openFile() {
        guard let space = browser.shownSpace else { return }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let format = pages.activePage?.pageEngine.registration.archiveFormat ?? .registered
        let actions = self
        Task { @MainActor in
            let panel = NSOpenPanel()
            panel.allowedContentTypes = BrowserLocalFileOpenPolicy.contentTypes(archive: format)
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.title = String(localized: "Open File")
            panel.prompt = String(localized: "Open")
            let response: NSApplication.ModalResponse
            if let window = NSApp.keyWindow {
                response = await panel.beginSheetModal(for: window)
            } else {
                response = panel.runModal()
            }
            guard response == .OK else { return }
            actions.openLocalDocuments(panel.urls, in: assignment)
        }
    }

    func openLocalDocuments(
        _ urls: [URL],
        in assignment: BrowserSpaceRuntimeAssignment
    ) {
        var selected: URL?
        for url in urls where BrowserCorePolicy.acceptsLocalDocument(url) {
            guard browser.openNewTab(url: url, matching: assignment) != nil else { continue }
            selected = url
        }
        guard let selected else { return }
        pages.select()
        pages.load(selected)
        chrome.dismissCommandPalette()
    }

    // MARK: - Page

    /// Moves the shown page to `engine`, which loads what it showed there.
    func movePage(to engine: EngineKind) {
        pages.activePage?.corePage.move(to: engine)
    }

    /// Translates the whole shown page, which its translation toolbar then
    /// follows.
    func translatePage() {
        pages.activePage?.translation.present()
    }

    func copyPageLink() {
        guard pages.copyPageLink() else { return }
        chrome.showURLCopiedFeedback()
    }

    func copyPageLinkAsMarkdown() {
        guard pages.copyPageLinkAsMarkdown() else { return }
        chrome.showURLCopiedFeedback()
    }

    func toggleContentBlocking() {
        guard let space = browser.shownSpace else { return }
        var preferences = space.settings.browsingPreferences
        preferences.contentBlocking = preferences.contentBlocking.switched
        browser.updateBrowsingPreferences(preferences, in: space.id)
        Task { await pages.reconcileContentBlocking() }
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
        guard let tab = browser.shownTab, browser.togglePin(tab.id) else { return }
        pages.select()
    }

    func duplicateSelectedTab() {
        guard browser.duplicateSelectedTab() != nil else { return }
        pages.reconcile()
        pages.select()
    }

    func reopenClosedTab() {
        guard browser.reopenClosedTab() else { return }
        pages.select()
    }

    func cleanupCurrentTabs() {
        browser.cleanupCurrentTabs()
        pages.reconcile()
        pages.select()
    }

    func archiveSelectedTab() {
        guard browser.archiveSelectedTab() != nil else { return }
        pages.reconcile()
        pages.select()
    }

    func selectPreviousTab() {
        selectAdjacentTab(.previous)
    }

    func selectNextTab() {
        selectAdjacentTab(.next)
    }

    func selectMostRecentTab() {
        guard browser.showMostRecentTab() else { return }
        pages.select()
    }

    func selectAdjacentTab(_ direction: AdjacentDirection) {
        guard browser.selectAdjacentTab(direction) != nil else { return }
        pages.select()
    }

    /// Shows the tab a numbered command leads to, in the Space this window shows.
    func selectTab(_ tabID: UUID?, in spaceID: UUID) {
        guard let tabID, spaceID == browser.selectedSpaceID else { return }
        browser.selectTab(tabID)
        pages.select()
    }

    // MARK: - Split View

    /// The cards the content area is presenting right now, focused member
    /// included. One element means the selection is an ordinary tab.
    var presentedSplitMembers: [TabStateModel] {
        browser.shownCards
    }

    /// Adds the next eligible tab in the selected tab's own section to its
    /// split, creating the group when there is none yet.
    func splitWithNextTab() {
        guard let space = browser.shownSpace,
            let selectedTabID = browser.selectedTabID(in: space.id),
            let candidate = browser.nextSplitJoinCandidate,
            browser.addTabToSplit(
                BrowserTabDragItem(tabID: candidate, spaceID: space.id, profileID: space.profileID),
                joining: selectedTabID,
                at: nil
            )
        else { return }
        pages.select()
    }

    /// Moves focus one card along the presented run and wraps at both ends.
    ///
    /// Focus is selection, so this is `selectTab` and nothing else: the URL
    /// bar, find bar, and every page command follow the selection pipeline they
    /// already followed before splits existed.
    func focusAdjacentSplitCard(offset: Int) {
        let members = presentedSplitMembers
        guard members.count > 1,
            let selectedTabID = browser.shownTab?.id,
            let index = members.firstIndex(where: { $0.id == selectedTabID })
        else { return }
        let count = members.count
        let wrappedIndex = (index + offset % count + count) % count
        browser.selectTab(members[wrappedIndex].id)
        pages.select()
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
        guard let space = browser.shownSpace,
            let selectedTabID = browser.selectedTabID(in: space.id)
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
        guard let space = browser.shownSpace,
            let selectedTabID = browser.selectedTabID(in: space.id)
        else { return }
        browser.moveSplitMember(
            selectedTabID,
            by: offset,
            matching: BrowserSpaceRuntimeAssignment(space: space)
        )
    }

    /// Drops the focused card out of its split and leaves it an ordinary tab.
    func removeSelectedTabFromSplit() {
        guard let space = browser.shownSpace,
            let selectedTabID = browser.selectedTabID(in: space.id),
            browser.removeTabFromSplit(
                selectedTabID,
                matching: BrowserSpaceRuntimeAssignment(space: space)
            )
        else { return }
        pages.select()
    }

    /// "Separate All Tabs": every card in the presented split becomes a tab.
    func separateSplitTabs() {
        guard let space = browser.shownSpace,
            let selectedTabID = browser.selectedTabID(in: space.id),
            browser.dissolveSplit(
                containing: selectedTabID,
                matching: BrowserSpaceRuntimeAssignment(space: space)
            )
        else { return }
        pages.select()
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
        pages.selectSpace(in: browser)
    }

    func selectSpace(_ spaceID: UUID) {
        browser.selectSpace(spaceID)
        pages.selectSpace(in: browser)
    }
}
