import AppKit
import SwiftUI

struct BrowserCommands: Commands {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let chrome: BrowserChromeState
    let shortcuts: BrowserShortcutStore
    let softwareUpdates: BrowserSoftwareUpdateService
    let spaceAccess: BrowserSpaceAccessController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.layoutDirection) private var layoutDirection
    @FocusedValue(\.browserCommandContext) private var focusedContext

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…", systemImage: "arrow.triangle.2.circlepath") {
                softwareUpdates.checkForUpdates()
            }
            .disabled(!softwareUpdates.isEnabled)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…", systemImage: "gearshape") {
                commandBrowser.openSettings()
                commandPages.select(session: commandBrowser.presented)
                if focusedContext == nil { openWindow(id: BrowserSceneID.browser.rawValue) }
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .newItem) {
            Button(
                "New Window",
                systemImage: ShortcutCommand.newWindow.symbol,
                action: actions.openNewWindow
            )
            .keyboardShortcut(shortcut(.newWindow))
            Button(
                "New Blank Window", systemImage: ShortcutCommand.newBlankWindow.symbol,
                action: actions.openBlankWindow
            )
            .keyboardShortcut(shortcut(.newBlankWindow))
            .disabled(commandBrowser.isPrivateBrowsing)
            Button(
                "New Tab",
                systemImage: ShortcutCommand.newTab.symbol,
                action: actions.openNewTab
            )
            .keyboardShortcut(shortcut(.newTab))
            Button(
                "New Quick Window",
                systemImage: ShortcutCommand.newQuickWindow.symbol,
                action: actions.openQuickWindow
            )
            .keyboardShortcut(shortcut(.newQuickWindow))
            Button(
                "New Private Window",
                systemImage: ShortcutCommand.newPrivateWindow.symbol,
                action: actions.openPrivateWindow
            )
            .keyboardShortcut(shortcut(.newPrivateWindow))
            Divider()
            Button(
                "Open File…",
                systemImage: ShortcutCommand.openFile.symbol,
                action: actions.openFile
            )
            .keyboardShortcut(shortcut(.openFile))
            .disabled(!actions.canPerform(.openFile))
            Divider()
            Button(
                "Close Current Tab or Window",
                systemImage: ShortcutCommand.closeTabOrWindow.symbol,
                action: closeTabOrWindow
            )
            .keyboardShortcut(shortcut(.closeTabOrWindow))
            Button(
                "Close Window",
                systemImage: ShortcutCommand.closeWindow.symbol,
                action: actions.closeKeyWindow
            )
            .keyboardShortcut(shortcut(.closeWindow))
        }

        CommandMenu("Navigate") {
            Button(
                "Open Location",
                systemImage: ShortcutCommand.openLocation.symbol,
                action: actions.openLocation
            )
            .keyboardShortcut(shortcut(.openLocation))
            Divider()
            Button(
                "Back",
                systemImage: ShortcutCommand.back.symbol,
                action: commandPages.goBack
            )
            .keyboardShortcut(shortcut(.back))
            .disabled(!commandPages.canGoBack)
            Button(
                "Forward",
                systemImage: ShortcutCommand.forward.symbol,
                action: commandPages.goForward
            )
            .keyboardShortcut(shortcut(.forward))
            .disabled(!commandPages.canGoForward)
            Button(
                "Reload Page",
                systemImage: ShortcutCommand.reloadPage.symbol
            ) {
                commandPages.reloadOrStop(in: commandBrowser.presented)
            }
            .keyboardShortcut(shortcut(.reloadPage))
            .disabled(!actions.canReloadSelectedTab)
            Button(
                "Stop Loading",
                systemImage: ShortcutCommand.stopLoading.symbol,
                action: commandPages.stopLoading
            )
            .keyboardShortcut(shortcut(.stopLoading))
            .disabled(!commandPages.isLoading)
            Button(
                "Reload from Origin",
                systemImage: ShortcutCommand.reloadFromOrigin.symbol
            ) {
                commandPages.reloadFromOrigin(in: commandBrowser.presented)
            }
            .keyboardShortcut(shortcut(.reloadFromOrigin))
            .disabled(!actions.canReloadSelectedTab)
        }

        CommandMenu("Tabs") {
            Button(
                "Pin or Unpin Tab",
                systemImage: ShortcutCommand.toggleSelectedTabPinned.symbol,
                action: actions.toggleSelectedTabPinned
            )
            .keyboardShortcut(shortcut(.toggleSelectedTabPinned))
            .disabled(commandBrowser.selectedTab == nil)
            Button(
                "Duplicate Tab",
                systemImage: ShortcutCommand.duplicateTab.symbol,
                action: actions.duplicateSelectedTab
            )
            .keyboardShortcut(shortcut(.duplicateTab))
            .disabled(!actions.canDuplicateSelectedTab)
            Button(
                "Reopen Closed Tab",
                systemImage: ShortcutCommand.reopenClosedTab.symbol,
                action: actions.reopenClosedTab
            )
            .keyboardShortcut(shortcut(.reopenClosedTab))
            .disabled(commandBrowser.selectedSpace?.archivedTabs.isEmpty != false)
            Button(
                "Clear Unpinned Tabs",
                systemImage: ShortcutCommand.clearUnpinnedTabs.symbol,
                action: actions.cleanupCurrentTabs
            )
            .keyboardShortcut(shortcut(.clearUnpinnedTabs))
            Button(
                "Archive Tab",
                systemImage: ShortcutCommand.archiveTab.symbol,
                action: actions.archiveSelectedTab
            )
            .keyboardShortcut(shortcut(.archiveTab))
            .disabled(!actions.canArchiveSelectedTab)
            Divider()
            Button(
                "Previous Tab",
                systemImage: ShortcutCommand.previousTab.symbol,
                action: actions.selectPreviousTab
            )
            .keyboardShortcut(shortcut(.previousTab))
            Button(
                "Next Tab",
                systemImage: ShortcutCommand.nextTab.symbol,
                action: actions.selectNextTab
            )
            .keyboardShortcut(shortcut(.nextTab))
            Button(
                "Most Recent Tab",
                systemImage: ShortcutCommand.mostRecentTab.symbol,
                action: actions.selectMostRecentTab
            )
            .keyboardShortcut(shortcut(.mostRecentTab))

            Divider()
            Button(
                "Split With Next Tab",
                systemImage: ShortcutCommand.splitWithNextTab.symbol,
                action: actions.splitWithNextTab
            )
            .keyboardShortcut(shortcut(.splitWithNextTab))
            .disabled(!actions.canSplitWithNextTab)
            Button(
                "Focus Next Split Card",
                systemImage: ShortcutCommand.focusNextSplitCard.symbol
            ) {
                actions.focusAdjacentSplitCard(offset: 1)
            }
            .keyboardShortcut(shortcut(.focusNextSplitCard))
            .disabled(!actions.isSelectedTabInSplit)
            Button(
                "Focus Previous Split Card",
                systemImage: ShortcutCommand.focusPreviousSplitCard.symbol
            ) {
                actions.focusAdjacentSplitCard(offset: -1)
            }
            .keyboardShortcut(shortcut(.focusPreviousSplitCard))
            .disabled(!actions.isSelectedTabInSplit)
            Button(
                "Move Split Card Left",
                systemImage: ShortcutCommand.moveSplitCardLeft.symbol
            ) {
                actions.moveFocusedSplitCard(.left)
            }
            .keyboardShortcut(shortcut(.moveSplitCardLeft))
            .disabled(!actions.canMoveFocusedSplitCard(.left))
            Button(
                "Move Split Card Right",
                systemImage: ShortcutCommand.moveSplitCardRight.symbol
            ) {
                actions.moveFocusedSplitCard(.right)
            }
            .keyboardShortcut(shortcut(.moveSplitCardRight))
            .disabled(!actions.canMoveFocusedSplitCard(.right))
            Button(
                "Remove Tab From Split",
                systemImage: ShortcutCommand.removeTabFromSplit.symbol,
                action: actions.removeSelectedTabFromSplit
            )
            .keyboardShortcut(shortcut(.removeTabFromSplit))
            .disabled(!actions.isSelectedTabInSplit)
            Button(
                "Separate All Tabs",
                systemImage: ShortcutCommand.separateSplitTabs.symbol,
                action: actions.separateSplitTabs
            )
            .keyboardShortcut(shortcut(.separateSplitTabs))
            .disabled(!actions.isSelectedTabInSplit)

            Divider()
            let tabSelections = actions.numberedSelections
            ForEach(1...9, id: \.self) { number in
                let command = ShortcutCommand.selecting(.tab, number: number)
                Button("Select Tab \(number)", systemImage: "\(number).square") {
                    command.map(actions.perform)
                }
                .keyboardShortcut(tabSelectionShortcut(number))
                .disabled(command.flatMap { tabSelections[$0] } == nil)
            }
        }

        CommandMenu("Spaces") {
            Button(
                "Previous Space",
                systemImage: ShortcutCommand.previousSpace.symbol,
                action: actions.selectPreviousSpace
            )
            .keyboardShortcut(shortcut(.previousSpace))
            Button(
                "Next Space",
                systemImage: ShortcutCommand.nextSpace.symbol,
                action: actions.selectNextSpace
            )
            .keyboardShortcut(shortcut(.nextSpace))
            Divider()
            let spaceSelections = actions.numberedSelections
            ForEach(1...9, id: \.self) { number in
                let command = ShortcutCommand.selecting(.space, number: number)
                Button("Select Space \(number)", systemImage: "\(number).square") {
                    command.map(actions.perform)
                }
                .keyboardShortcut(spaceSelectionShortcut(number))
                .disabled(command.flatMap { spaceSelections[$0] } == nil)
            }
        }

        CommandMenu("Page") {
            // Features the running engine declares absent are left out of the
            // menu rather than shown permanently dimmed.
            if ShortcutCommand.toggleTranslationToolbar.isOfferedByCurrentEngine {
                Button("Translate Page", systemImage: "translate") {
                    commandPages.activePage?.translation.present()
                }
                .disabled(!commandPages.hasActivePage || commandPages.readerModeState.isActive)
            }
            if ShortcutCommand.toggleReaderMode.isOfferedByCurrentEngine {
                Button(
                    commandPages.readerModeActionTitle,
                    systemImage: ShortcutCommand.toggleReaderMode.symbol,
                    action: commandPages.toggleReaderMode
                )
                .keyboardShortcut(shortcut(.toggleReaderMode))
                .disabled(!commandPages.readerModeState.canToggle)
            }
            if ShortcutCommand.toggleContentBlocking.isOfferedByCurrentEngine {
                Button(
                    actions.contentBlockingActionTitle,
                    systemImage: ShortcutCommand.toggleContentBlocking.symbol,
                    action: actions.toggleContentBlocking
                )
                .keyboardShortcut(shortcut(.toggleContentBlocking))
                .disabled(commandBrowser.selectedSpace == nil)
            }
            Divider()
            Button(
                "Find in Page",
                systemImage: ShortcutCommand.findInPage.symbol,
                action: commandPages.presentFind
            )
            .keyboardShortcut(shortcut(.findInPage))
            .disabled(!commandPages.hasActivePage)
            Divider()
            Button(
                "Zoom In",
                systemImage: ShortcutCommand.zoomIn.symbol,
                action: actions.zoomIn
            )
            .keyboardShortcut(shortcut(.zoomIn))
            .disabled(!commandPages.hasActivePage || commandPages.activePage?.developerViewport != nil)
            Button(
                "Zoom Out",
                systemImage: ShortcutCommand.zoomOut.symbol,
                action: actions.zoomOut
            )
            .keyboardShortcut(shortcut(.zoomOut))
            .disabled(!commandPages.hasActivePage || commandPages.activePage?.developerViewport != nil)
            Button(
                "Actual Size",
                systemImage: ShortcutCommand.actualSize.symbol,
                action: actions.resetZoom
            )
            .keyboardShortcut(shortcut(.actualSize))
            .disabled(!commandPages.hasActivePage || commandPages.activePage?.developerViewport != nil)
            Divider()
            Button(
                "Copy Page Link",
                systemImage: ShortcutCommand.copyPageLink.symbol,
                action: actions.copyPageLink
            )
            .keyboardShortcut(shortcut(.copyPageLink))
            .disabled(!commandPages.hasActivePage)
            Button(
                "Copy Page Link as Markdown",
                systemImage: ShortcutCommand.copyPageLinkAsMarkdown.symbol,
                action: actions.copyPageLinkAsMarkdown
            )
            .keyboardShortcut(shortcut(.copyPageLinkAsMarkdown))
            .disabled(!commandPages.hasActivePage)
            Button(
                "Share…",
                systemImage: ShortcutCommand.sharePage.symbol,
                action: commandPages.sharePage
            )
            .keyboardShortcut(shortcut(.sharePage))
            .disabled(!commandPages.hasActivePage)
            Button(
                "Export as PDF…",
                systemImage: ShortcutCommand.exportPDF.symbol,
                action: commandPages.exportPDF
            )
            .keyboardShortcut(shortcut(.exportPDF))
            .disabled(!actions.canPerform(.exportPDF))
            Button(
                "Save Web Archive…",
                systemImage: ShortcutCommand.saveWebArchive.symbol,
                action: commandPages.exportWebArchive
            )
            .keyboardShortcut(shortcut(.saveWebArchive))
            .disabled(!actions.canPerform(.saveWebArchive))
        }

        CommandMenu("Develop") {
            developerToolbarToggle
                .keyboardShortcut(shortcut(.toggleDeveloperToolbar))
            Divider()
            Button(
                "Show Web Inspector",
                systemImage: ShortcutCommand.showWebInspector.symbol,
                action: commandPages.showWebInspector
            )
            .keyboardShortcut(shortcut(.showWebInspector))
            .disabled(!actions.canPerform(.showWebInspector))
        }

        CommandGroup(replacing: .printItem) {
            Button(
                "Print…",
                systemImage: ShortcutCommand.printPage.symbol,
                action: commandPages.printPage
            )
            .keyboardShortcut(shortcut(.printPage))
            .disabled(!actions.canPerform(.printPage))
        }

        CommandGroup(after: .sidebar) {
            if ShortcutCommand.toggleTranslationToolbar.isOfferedByCurrentEngine {
                Toggle(
                    isOn: Binding(
                        get: { commandPages.activePage?.translation.showsToolbar == true },
                        set: { commandPages.activePage?.translation.setToolbarVisible($0) }
                    )
                ) {
                    Label(
                        "Show Translation Toolbar",
                        systemImage: ShortcutCommand.toggleTranslationToolbar.symbol)
                }
                .keyboardShortcut(shortcut(.toggleTranslationToolbar))
                .disabled(!commandPages.hasActivePage || commandPages.readerModeState.isActive)
            }
            developerToolbarToggle
            Button(
                "Toggle Sidebar",
                systemImage: ShortcutCommand.toggleSidebar.symbol,
                action: actions.toggleSidebar
            )
            .keyboardShortcut(shortcut(.toggleSidebar))
        }

        CommandGroup(replacing: .help) {
            Button("Getting Started with Crest") {
                commandBrowser.openGettingStarted()
                commandPages.select(session: commandBrowser.presented)
            }
        }

        CommandGroup(after: .toolbar) {
            Button(
                "Show History",
                systemImage: ShortcutCommand.showHistory.symbol,
                action: commandChrome.presentHistory
            )
            .keyboardShortcut(shortcut(.showHistory))
            Button(
                "Show Archive",
                systemImage: ShortcutCommand.showArchive.symbol,
                action: actions.presentArchive
            )
            .keyboardShortcut(shortcut(.showArchive))
            .disabled(commandBrowser.selectedSpace == nil)
            Button(
                "Show Downloads",
                systemImage: ShortcutCommand.showDownloads.symbol,
                action: actions.presentDownloads
            )
            .keyboardShortcut(shortcut(.showDownloads))
        }
    }

    private var developerToolbarToggle: some View {
        Toggle(
            "Show Developer Toolbar",
            isOn: Binding(
                get: { commandPages.activePage?.isDeveloperModeEnabled == true },
                set: { commandPages.activePage?.setDeveloperToolbarVisible($0) }
            )
        )
        .disabled(!commandPages.hasActivePage)
    }

    private var actions: BrowserCommandActions {
        BrowserCommandActions(
            browser: commandBrowser,
            pages: commandPages,
            chrome: commandChrome,
            openWindow: openWindow,
            spaceAccess: focusedContext?.spaceAccess ?? spaceAccess,
            targetWindowID: focusedContext?.windowID,
            layoutDirection: layoutDirection,
        )
    }

    /// Without a focused browser window there is no tab to close, so ⌘W has to
    /// fall through to the window itself rather than to the fallback store.
    private func closeTabOrWindow() {
        guard focusedContext != nil else {
            actions.closeKeyWindow()
            return
        }
        actions.closeTabOrWindow()
    }

    private func shortcut(_ command: ShortcutCommand) -> KeyboardShortcut? {
        shortcuts.keyboardShortcut(for: command)
    }

    private func tabSelectionShortcut(_ number: Int) -> KeyboardShortcut? {
        ShortcutCommand.selecting(.tab, number: number).flatMap(shortcut)
    }

    private func spaceSelectionShortcut(_ number: Int) -> KeyboardShortcut? {
        ShortcutCommand.selecting(.space, number: number).flatMap(shortcut)
    }

    private var commandBrowser: BrowserStore {
        focusedContext?.browser ?? browser
    }

    private var commandPages: BrowserPagePool {
        focusedContext?.pages ?? pages
    }

    private var commandChrome: BrowserChromeState {
        focusedContext?.chrome ?? chrome
    }
}
