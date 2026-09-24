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
    var spaceAccess = BrowserSpaceAccessController()
    /// The window a Quick Window should hand its result back to, when the
    /// command was issued from a focused browser window.
    var targetWindowID: BrowserWindowID?
    /// Which way the cards are laid out, for the commands that name a side of
    /// the screen. Only the split-card moves read it; see
    /// `BrowserSplitCardMoveDirection`.
    var layoutDirection: LayoutDirection = .leftToRight

    /// The commands the launcher offers on macOS.
    ///
    /// Numbered tab and Space selection are left out: they are chords, not
    /// things anyone searches for by name, and the launcher already lists the
    /// tabs themselves.
    static let paletteCommands: [ShortcutCommand] = [
        .newWindow,
        .openFile,
        .newBlankWindow,
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
        .showHistory,
        .showArchive,
        .showDownloads,
        .showWebInspector,
        .toggleDeveloperToolbar,
        .toggleTranslationToolbar,
    ]

    func paletteRegistry(
        shortcuts: BrowserShortcutStore?
    ) -> BrowserCommandPaletteCommandRegistry {
        BrowserCommandPaletteCommandRegistry(
            commands: Self.paletteCommands.filter(\.isOfferedByCurrentEngine),
            shortcut: { shortcuts?.shortcut(for: $0) },
            perform: perform
        )
    }

    func perform(_ command: ShortcutCommand) {
        let route = route(command)
        guard route.isAvailable else { return }
        route.run()
    }

    /// Availability belongs to the same command route used by menus and keys.
    /// In particular, a disabled split shortcut must leave text selection alone.
    func canPerform(_ command: ShortcutCommand) -> Bool {
        route(command).isAvailable
    }

    /// What a command does in the Mac shell, and whether it can do it now.
    private struct Route {
        var isAvailable = true
        let run: @MainActor () -> Void
    }

    /// The one place that turns each command into what the Mac shell does.
    private func route(_ command: ShortcutCommand) -> Route {
        switch command.kind {
        case .newWindow: Route(run: openNewWindow)
        case .newBlankWindow:
            Route(isAvailable: !browser.isPrivateBrowsing && browser.selectedSpace != nil, run: openBlankWindow)
        case .newTab: Route(run: openNewTab)
        case .openLocation: Route(run: openLocation)
        case .openFile:
            Route(
                isAvailable: browser.selectedSpace != nil && supportsEngineCapability(.localFiles), run: openFile)
        case .newQuickWindow: Route(isAvailable: browser.selectedSpace != nil, run: openQuickWindow)
        case .newPrivateWindow: Route(run: openPrivateWindow)
        case .closeTabOrWindow: Route(run: closeTabOrWindow)
        case .closeWindow: Route(run: closeKeyWindow)
        case .back: Route(isAvailable: pages.canGoBack, run: pages.goBack)
        case .forward: Route(isAvailable: pages.canGoForward, run: pages.goForward)
        case .reloadPage:
            Route(isAvailable: canReloadSelectedTab) { pages.reloadOrStop(in: browser.presented) }
        case .stopLoading: Route(isAvailable: pages.isLoading, run: pages.stopLoading)
        case .reloadFromOrigin:
            Route(isAvailable: canReloadSelectedTab) { pages.reloadFromOrigin(in: browser.presented) }
        case .toggleSelectedTabPinned:
            Route(isAvailable: browser.selectedTab != nil, run: toggleSelectedTabPinned)
        case .duplicateTab: Route(isAvailable: canDuplicateSelectedTab, run: duplicateSelectedTab)
        case .reopenClosedTab:
            Route(isAvailable: browser.selectedSpace?.archivedTabs.isEmpty == false, run: reopenClosedTab)
        case .clearUnpinnedTabs: Route(run: cleanupCurrentTabs)
        case .archiveTab: Route(isAvailable: canArchiveSelectedTab, run: archiveSelectedTab)
        case .previousTab: Route(run: selectPreviousTab)
        case .nextTab: Route(run: selectNextTab)
        case .mostRecentTab: Route(run: selectMostRecentTab)
        case .splitWithNextTab: Route(isAvailable: canSplitWithNextTab, run: splitWithNextTab)
        case .focusNextSplitCard:
            Route(isAvailable: isSelectedTabInSplit) { focusAdjacentSplitCard(offset: 1) }
        case .focusPreviousSplitCard:
            Route(isAvailable: isSelectedTabInSplit) { focusAdjacentSplitCard(offset: -1) }
        case .removeTabFromSplit: Route(isAvailable: isSelectedTabInSplit, run: removeSelectedTabFromSplit)
        case .separateSplitTabs: Route(isAvailable: isSelectedTabInSplit, run: separateSplitTabs)
        case .moveSplitCardLeft:
            Route(isAvailable: canMoveFocusedSplitCard(.left)) { moveFocusedSplitCard(.left) }
        case .moveSplitCardRight:
            Route(isAvailable: canMoveFocusedSplitCard(.right)) { moveFocusedSplitCard(.right) }
        case .previousSpace: Route(run: selectPreviousSpace)
        case .nextSpace: Route(run: selectNextSpace)
        case .toggleReaderMode:
            Route(
                isAvailable: supportsPageCapability(.reader) && pages.readerModeState.canToggle,
                run: pages.toggleReaderMode)
        case .toggleContentBlocking:
            Route(
                isAvailable: browser.selectedSpace != nil && supportsEngineCapability(.contentBlocking),
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
        case .showArchive: Route(isAvailable: browser.selectedSpace != nil, run: presentArchive)
        case .showDownloads: Route(isAvailable: supportsEngineCapability(.downloads), run: presentDownloads)
        case .showWebInspector:
            Route(isAvailable: supportsPageCapability(.inspector), run: pages.showWebInspector)
        case .toggleTranslationToolbar:
            Route(isAvailable: supportsPageCapability(.translation) && !pages.readerModeState.isActive) {
                guard let page = pages.activePage, !page.readerModeState.isActive else { return }
                page.translation.toggleToolbarVisibility()
            }
        case .toggleDeveloperToolbar:
            Route(isAvailable: pages.hasActivePage) {
                if let page = pages.activePage {
                    page.setDeveloperToolbarVisible(!page.isDeveloperModeEnabled)
                }
            }
        case .selectNumbered:
            if let selection = numberedSelections[command] {
                switch selection.target.kind {
                case .tab: Route { selectTab(at: selection.index) }
                case .space: Route { selectSpace(at: selection.index) }
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
    /// moment before a page exists. The active page's own engine still answers
    /// whenever there is one.
    private func supportsEngineCapability(_ capability: EngineCapability) -> Bool {
        (pages.activePage?.pageEngine.registration ?? BrowserEngineRegistration.current)
            .supports(capability)
    }

    /// Where each numbered selection command leads right now, per the core.
    var numberedSelections: [ShortcutCommand: BrowserNumberedSelection] {
        BrowserCorePolicy.numberedSelections(tabCount: orderedTabs.count, spaceCount: browser.session.spaces.count)
    }

    // MARK: - Windows

    func openNewTab() {
        chrome.openNewTab(
            isStartPageSelected: browser.selectedTab?.isStartPage == true
        )
    }

    func openNewWindow() {
        let request = BrowserMacWindowRequest.normal(sourceWindowID: targetWindowID)
        if let host = BrowserMacWindowPresentation.host { host.openWindow(request) }
        else { openWindow(id: BrowserSceneID.browser.rawValue, value: request) }
    }

    func openBlankWindow() {
        guard !browser.isPrivateBrowsing, let space = browser.selectedSpace, !spaceAccess.isLocked(space) else {
            return
        }
        let request = BrowserMacWindowRequest.temporary(
            sourceWindowID: targetWindowID, assignment: BrowserSpaceRuntimeAssignment(space: space))
        if let host = BrowserMacWindowPresentation.host { host.openWindow(request) }
        else { openWindow(id: BrowserSceneID.blankWindow.rawValue, value: request) }
    }

    func openPrivateWindow() {
        if let host = BrowserMacWindowPresentation.host { host.openPrivateWindow() }
        else { openWindow(id: BrowserSceneID.privateBrowser.rawValue) }
    }

    func openQuickWindow() {
        guard let space = browser.selectedSpace else { return }
        let request = BrowserQuickWindowRequest.empty(
            spaceAssignment: BrowserSpaceRuntimeAssignment(space: space), targetWindowID: targetWindowID)
        if let host = BrowserMacWindowPresentation.host { host.openQuickWindow(request) }
        else { openWindow(id: BrowserSceneID.quickWindow.rawValue, value: request) }
    }

    func closeKeyWindow() {
        NSApp.keyWindow?.performClose(nil)
    }

    func closeTabOrWindow() {
        guard let selectedTab = browser.selectedTab else {
            closeKeyWindow()
            return
        }

        switch BrowserCorePolicy.tabDismissal(
            for: selectedTab,
            tabCount: orderedTabs.count
        ) {
        case .closeTab:
            if selectedTab.isStartPage {
                browser.closeTab(selectedTab.id)
                pages.reconcile(session: browser.session)
                pages.select(session: browser.presented)
            } else {
                archiveSelectedTab()
            }
        case .unloadPage:
            guard let space = browser.selectedSpace else { return }
            if BrowserDurableTabCloseAction(
                browser: browser, spaceAccess: spaceAccess,
                closePage: { pages.closeDurablePage($0, discardState: $1) }
            ).perform(
                BrowserTabRuntimeAssignment(
                    tabID: selectedTab.id, spaceID: space.id, profileID: space.profile.id
                ))
            {
                pages.select(session: browser.presented)
            }
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

    /// Opens local documents as ordinary tabs in the Space on screen.
    ///
    /// The archive entry follows the active page's engine, not the platform: a
    /// panel offering a `.webarchive` to Chromium would be offering a document
    /// the engine cannot read.
    func openFile() {
        guard let space = browser.selectedSpace else { return }
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let format = pages.activePage?.pageEngine.documentServices?.archiveFormat ?? .registered
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
        pages.select(session: browser.presented)
        pages.load(selected)
        chrome.dismissCommandPalette()
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
        pages.select(session: browser.presented)
    }

    func duplicateSelectedTab() {
        guard browser.duplicateSelectedTab() != nil else { return }
        pages.reconcile(session: browser.session)
        pages.select(session: browser.presented)
    }

    func reopenClosedTab() {
        guard
            let archived = browser.selectedSpace?.archivedTabs.max(
                by: { $0.archivedAt < $1.archivedAt }
            )
        else { return }
        browser.restoreArchivedTab(archived.id)
        browser.selectTab(archived.id)
        pages.select(session: browser.presented)
    }

    func cleanupCurrentTabs() {
        browser.cleanupCurrentTabs()
        pages.reconcile(session: browser.session)
        pages.select(session: browser.presented)
    }

    func archiveSelectedTab() {
        guard browser.archiveSelectedTab() != nil else { return }
        pages.reconcile(session: browser.session)
        pages.select(session: browser.presented)
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
        pages.select(session: browser.presented)
    }

    func selectTab(offset: Int) {
        guard browser.selectAdjacentTab(offset: offset) != nil else { return }
        pages.select(session: browser.presented)
    }

    func selectTab(at index: Int) {
        guard orderedTabs.indices.contains(index) else { return }
        browser.selectTab(orderedTabs[index].id)
        pages.select(session: browser.presented)
    }

    // MARK: - Split View

    /// The cards the content area is presenting right now, focused member
    /// included. One element means the selection is an ordinary tab.
    var presentedSplitMembers: [BrowserTab] {
        guard let space = browser.selectedSpace else { return [] }
        return space.presentedSplitMembers(for: browser.selectedTabID(in: space.id))
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
            let selectedTabID = browser.selectedTabID(in: space.id),
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
        pages.select(session: browser.presented)
    }

    /// Moves focus one card along the presented run and wraps at both ends.
    ///
    /// Focus is selection, so this is `selectTab` and nothing else: the URL
    /// bar, find bar, and every page command follow the selection pipeline they
    /// already followed before splits existed.
    func focusAdjacentSplitCard(offset: Int) {
        let members = presentedSplitMembers
        guard members.count > 1,
            let selectedTabID = browser.selectedTab?.id,
            let index = members.firstIndex(where: { $0.id == selectedTabID })
        else { return }
        let count = members.count
        let wrappedIndex = (index + offset % count + count) % count
        browser.selectTab(members[wrappedIndex].id)
        pages.select(session: browser.presented)
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
        guard let space = browser.selectedSpace,
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
        guard let space = browser.selectedSpace,
            let selectedTabID = browser.selectedTabID(in: space.id),
            browser.removeTabFromSplit(
                selectedTabID,
                matching: BrowserSpaceRuntimeAssignment(space: space)
            )
        else { return }
        pages.select(session: browser.presented)
    }

    /// "Separate All Tabs": every card in the presented split becomes a tab.
    func separateSplitTabs() {
        guard let space = browser.selectedSpace,
            let selectedTabID = browser.selectedTabID(in: space.id),
            browser.dissolveSplit(
                containing: selectedTabID,
                matching: BrowserSpaceRuntimeAssignment(space: space)
            )
        else { return }
        pages.select(session: browser.presented)
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

    func selectSpace(at index: Int) {
        guard browser.session.spaces.indices.contains(index) else { return }
        browser.selectSpace(browser.session.spaces[index].id)
        pages.selectSpace(in: browser)
    }
}
