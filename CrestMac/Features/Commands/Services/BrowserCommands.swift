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
                systemImage: BrowserShortcutCommand.newWindow.paletteSymbol,
                action: actions.openNewWindow
            )
            .keyboardShortcut(shortcut(.newWindow))
            Button(
                "New Blank Window", systemImage: BrowserShortcutCommand.newBlankWindow.paletteSymbol,
                action: actions.openBlankWindow
            )
            .keyboardShortcut(shortcut(.newBlankWindow))
            .disabled(commandBrowser.isPrivateBrowsing)
            Button(
                "New Tab",
                systemImage: BrowserShortcutCommand.newTab.paletteSymbol,
                action: actions.openNewTab
            )
            .keyboardShortcut(shortcut(.newTab))
            Button(
                "New Quick Window",
                systemImage: BrowserShortcutCommand.newQuickWindow.paletteSymbol,
                action: actions.openQuickWindow
            )
            .keyboardShortcut(shortcut(.newQuickWindow))
            Button(
                "New Private Window",
                systemImage: BrowserShortcutCommand.newPrivateWindow.paletteSymbol,
                action: actions.openPrivateWindow
            )
            .keyboardShortcut(shortcut(.newPrivateWindow))
            Divider()
            Button(
                "Open File…",
                systemImage: BrowserShortcutCommand.openFile.paletteSymbol,
                action: actions.openFile
            )
            .keyboardShortcut(shortcut(.openFile))
            .disabled(!actions.canPerform(.openFile))
            Divider()
            Button(
                "Close Current Tab or Window",
                systemImage: BrowserShortcutCommand.closeTabOrWindow.paletteSymbol,
                action: closeTabOrWindow
            )
            .keyboardShortcut(shortcut(.closeTabOrWindow))
            Button(
                "Close Window",
                systemImage: BrowserShortcutCommand.closeWindow.paletteSymbol,
                action: actions.closeKeyWindow
            )
            .keyboardShortcut(shortcut(.closeWindow))
        }

        CommandMenu("Navigate") {
            Button(
                "Open Location",
                systemImage: BrowserShortcutCommand.openLocation.paletteSymbol,
                action: actions.openLocation
            )
            .keyboardShortcut(shortcut(.openLocation))
            Divider()
            Button(
                "Back",
                systemImage: BrowserShortcutCommand.back.paletteSymbol,
                action: commandPages.goBack
            )
            .keyboardShortcut(shortcut(.back))
            .disabled(!commandPages.canGoBack)
            Button(
                "Forward",
                systemImage: BrowserShortcutCommand.forward.paletteSymbol,
                action: commandPages.goForward
            )
            .keyboardShortcut(shortcut(.forward))
            .disabled(!commandPages.canGoForward)
            Button(
                "Reload Page",
                systemImage: BrowserShortcutCommand.reloadPage.paletteSymbol
            ) {
                commandPages.reloadOrStop(in: commandBrowser.presented)
            }
            .keyboardShortcut(shortcut(.reloadPage))
            .disabled(!actions.canReloadSelectedTab)
            Button(
                "Stop Loading",
                systemImage: BrowserShortcutCommand.stopLoading.paletteSymbol,
                action: commandPages.stopLoading
            )
            .keyboardShortcut(shortcut(.stopLoading))
            .disabled(!commandPages.isLoading)
            Button(
                "Reload from Origin",
                systemImage: BrowserShortcutCommand.reloadFromOrigin.paletteSymbol
            ) {
                commandPages.reloadFromOrigin(in: commandBrowser.presented)
            }
            .keyboardShortcut(shortcut(.reloadFromOrigin))
            .disabled(!actions.canReloadSelectedTab)
        }

        CommandMenu("Tabs") {
            Button(
                "Pin or Unpin Tab",
                systemImage: BrowserShortcutCommand.toggleSelectedTabPinned.paletteSymbol,
                action: actions.toggleSelectedTabPinned
            )
            .keyboardShortcut(shortcut(.toggleSelectedTabPinned))
            .disabled(commandBrowser.selectedTab == nil)
            Button(
                "Duplicate Tab",
                systemImage: BrowserShortcutCommand.duplicateTab.paletteSymbol,
                action: actions.duplicateSelectedTab
            )
            .keyboardShortcut(shortcut(.duplicateTab))
            .disabled(!actions.canDuplicateSelectedTab)
            Button(
                "Reopen Closed Tab",
                systemImage: BrowserShortcutCommand.reopenClosedTab.paletteSymbol,
                action: actions.reopenClosedTab
            )
            .keyboardShortcut(shortcut(.reopenClosedTab))
            .disabled(commandBrowser.selectedSpace?.archivedTabs.isEmpty != false)
            Button(
                "Clear Unpinned Tabs",
                systemImage: BrowserShortcutCommand.clearUnpinnedTabs.paletteSymbol,
                action: actions.cleanupCurrentTabs
            )
            .keyboardShortcut(shortcut(.clearUnpinnedTabs))
            Button(
                "Archive Tab",
                systemImage: BrowserShortcutCommand.archiveTab.paletteSymbol,
                action: actions.archiveSelectedTab
            )
            .keyboardShortcut(shortcut(.archiveTab))
            .disabled(!actions.canArchiveSelectedTab)
            Divider()
            Button(
                "Previous Tab",
                systemImage: BrowserShortcutCommand.previousTab.paletteSymbol,
                action: actions.selectPreviousTab
            )
            .keyboardShortcut(shortcut(.previousTab))
            Button(
                "Next Tab",
                systemImage: BrowserShortcutCommand.nextTab.paletteSymbol,
                action: actions.selectNextTab
            )
            .keyboardShortcut(shortcut(.nextTab))
            Button(
                "Most Recent Tab",
                systemImage: BrowserShortcutCommand.mostRecentTab.paletteSymbol,
                action: actions.selectMostRecentTab
            )
            .keyboardShortcut(shortcut(.mostRecentTab))

            Divider()
            Button(
                "Split With Next Tab",
                systemImage: BrowserShortcutCommand.splitWithNextTab.paletteSymbol,
                action: actions.splitWithNextTab
            )
            .keyboardShortcut(shortcut(.splitWithNextTab))
            .disabled(!actions.canSplitWithNextTab)
            Button(
                "Focus Next Split Card",
                systemImage: BrowserShortcutCommand.focusNextSplitCard.paletteSymbol
            ) {
                actions.focusAdjacentSplitCard(offset: 1)
            }
            .keyboardShortcut(shortcut(.focusNextSplitCard))
            .disabled(!actions.isSelectedTabInSplit)
            Button(
                "Focus Previous Split Card",
                systemImage: BrowserShortcutCommand.focusPreviousSplitCard.paletteSymbol
            ) {
                actions.focusAdjacentSplitCard(offset: -1)
            }
            .keyboardShortcut(shortcut(.focusPreviousSplitCard))
            .disabled(!actions.isSelectedTabInSplit)
            Button(
                "Move Split Card Left",
                systemImage: BrowserShortcutCommand.moveSplitCardLeft.paletteSymbol
            ) {
                actions.moveFocusedSplitCard(.left)
            }
            .keyboardShortcut(shortcut(.moveSplitCardLeft))
            .disabled(!actions.canMoveFocusedSplitCard(.left))
            Button(
                "Move Split Card Right",
                systemImage: BrowserShortcutCommand.moveSplitCardRight.paletteSymbol
            ) {
                actions.moveFocusedSplitCard(.right)
            }
            .keyboardShortcut(shortcut(.moveSplitCardRight))
            .disabled(!actions.canMoveFocusedSplitCard(.right))
            Button(
                "Remove Tab From Split",
                systemImage: BrowserShortcutCommand.removeTabFromSplit.paletteSymbol,
                action: actions.removeSelectedTabFromSplit
            )
            .keyboardShortcut(shortcut(.removeTabFromSplit))
            .disabled(!actions.isSelectedTabInSplit)
            Button(
                "Separate All Tabs",
                systemImage: BrowserShortcutCommand.separateSplitTabs.paletteSymbol,
                action: actions.separateSplitTabs
            )
            .keyboardShortcut(shortcut(.separateSplitTabs))
            .disabled(!actions.isSelectedTabInSplit)

            Divider()
            let tabSelections = actions.numberedSelections
            ForEach(1...9, id: \.self) { number in
                let command = BrowserShortcutCommand.tabSelection(number)
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
                systemImage: BrowserShortcutCommand.previousSpace.paletteSymbol,
                action: actions.selectPreviousSpace
            )
            .keyboardShortcut(shortcut(.previousSpace))
            Button(
                "Next Space",
                systemImage: BrowserShortcutCommand.nextSpace.paletteSymbol,
                action: actions.selectNextSpace
            )
            .keyboardShortcut(shortcut(.nextSpace))
            Divider()
            let spaceSelections = actions.numberedSelections
            ForEach(1...9, id: \.self) { number in
                let command = BrowserShortcutCommand.spaceSelection(number)
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
            if BrowserShortcutCommand.toggleTranslationToolbar.isOfferedByCurrentEngine {
                Button("Translate Page", systemImage: "translate") {
                    commandPages.activePage?.translation.present()
                }
                .disabled(!commandPages.hasActivePage || commandPages.readerModeState.isActive)
            }
            if BrowserShortcutCommand.toggleReaderMode.isOfferedByCurrentEngine {
                Button(
                    commandPages.readerModeActionTitle,
                    systemImage: BrowserShortcutCommand.toggleReaderMode.paletteSymbol,
                    action: commandPages.toggleReaderMode
                )
                .keyboardShortcut(shortcut(.toggleReaderMode))
                .disabled(!commandPages.readerModeState.canToggle)
            }
            if BrowserShortcutCommand.toggleContentBlocking.isOfferedByCurrentEngine {
                Button(
                    actions.contentBlockingActionTitle,
                    systemImage: BrowserShortcutCommand.toggleContentBlocking.paletteSymbol,
                    action: actions.toggleContentBlocking
                )
                .keyboardShortcut(shortcut(.toggleContentBlocking))
                .disabled(commandBrowser.selectedSpace == nil)
            }
            Divider()
            Button(
                "Find in Page",
                systemImage: BrowserShortcutCommand.findInPage.paletteSymbol,
                action: commandPages.presentFind
            )
            .keyboardShortcut(shortcut(.findInPage))
            .disabled(!commandPages.hasActivePage)
            Divider()
            Button(
                "Zoom In",
                systemImage: BrowserShortcutCommand.zoomIn.paletteSymbol,
                action: actions.zoomIn
            )
            .keyboardShortcut(shortcut(.zoomIn))
            .disabled(!commandPages.hasActivePage || commandPages.activePage?.developerViewport != nil)
            Button(
                "Zoom Out",
                systemImage: BrowserShortcutCommand.zoomOut.paletteSymbol,
                action: actions.zoomOut
            )
            .keyboardShortcut(shortcut(.zoomOut))
            .disabled(!commandPages.hasActivePage || commandPages.activePage?.developerViewport != nil)
            Button(
                "Actual Size",
                systemImage: BrowserShortcutCommand.actualSize.paletteSymbol,
                action: actions.resetZoom
            )
            .keyboardShortcut(shortcut(.actualSize))
            .disabled(!commandPages.hasActivePage || commandPages.activePage?.developerViewport != nil)
            Divider()
            Button(
                "Copy Page Link",
                systemImage: BrowserShortcutCommand.copyPageLink.paletteSymbol,
                action: actions.copyPageLink
            )
            .keyboardShortcut(shortcut(.copyPageLink))
            .disabled(!commandPages.hasActivePage)
            Button(
                "Copy Page Link as Markdown",
                systemImage: BrowserShortcutCommand.copyPageLinkAsMarkdown.paletteSymbol,
                action: actions.copyPageLinkAsMarkdown
            )
            .keyboardShortcut(shortcut(.copyPageLinkAsMarkdown))
            .disabled(!commandPages.hasActivePage)
            Button(
                "Share…",
                systemImage: BrowserShortcutCommand.sharePage.paletteSymbol,
                action: commandPages.sharePage
            )
            .keyboardShortcut(shortcut(.sharePage))
            .disabled(!commandPages.hasActivePage)
            Button(
                "Export as PDF…",
                systemImage: BrowserShortcutCommand.exportPDF.paletteSymbol,
                action: commandPages.exportPDF
            )
            .keyboardShortcut(shortcut(.exportPDF))
            .disabled(!actions.canPerform(.exportPDF))
            Button(
                "Save Web Archive…",
                systemImage: BrowserShortcutCommand.saveWebArchive.paletteSymbol,
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
                systemImage: BrowserShortcutCommand.showWebInspector.paletteSymbol,
                action: commandPages.showWebInspector
            )
            .keyboardShortcut(shortcut(.showWebInspector))
            .disabled(!actions.canPerform(.showWebInspector))
        }

        CommandGroup(replacing: .printItem) {
            Button(
                "Print…",
                systemImage: BrowserShortcutCommand.printPage.paletteSymbol,
                action: commandPages.printPage
            )
            .keyboardShortcut(shortcut(.printPage))
            .disabled(!actions.canPerform(.printPage))
        }

        CommandGroup(after: .sidebar) {
            if BrowserShortcutCommand.toggleTranslationToolbar.isOfferedByCurrentEngine {
                Toggle(
                    isOn: Binding(
                        get: { commandPages.activePage?.translation.showsToolbar == true },
                        set: { commandPages.activePage?.translation.setToolbarVisible($0) }
                    )
                ) {
                    Label(
                        "Show Translation Toolbar",
                        systemImage: BrowserShortcutCommand.toggleTranslationToolbar.paletteSymbol)
                }
                .keyboardShortcut(shortcut(.toggleTranslationToolbar))
                .disabled(!commandPages.hasActivePage || commandPages.readerModeState.isActive)
            }
            developerToolbarToggle
            Button(
                "Toggle Sidebar",
                systemImage: BrowserShortcutCommand.toggleSidebar.paletteSymbol,
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
                systemImage: BrowserShortcutCommand.showHistory.paletteSymbol,
                action: commandChrome.presentHistory
            )
            .keyboardShortcut(shortcut(.showHistory))
            Button(
                "Show Archive",
                systemImage: BrowserShortcutCommand.showArchive.paletteSymbol,
                action: actions.presentArchive
            )
            .keyboardShortcut(shortcut(.showArchive))
            .disabled(commandBrowser.selectedSpace == nil)
            Button(
                "Show Downloads",
                systemImage: BrowserShortcutCommand.showDownloads.paletteSymbol,
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

    private func shortcut(_ command: BrowserShortcutCommand) -> KeyboardShortcut? {
        shortcuts.keyboardShortcut(for: command)
    }

    private func tabSelectionShortcut(_ number: Int) -> KeyboardShortcut? {
        BrowserShortcutCommand.tabSelection(number).flatMap(shortcut)
    }

    private func spaceSelectionShortcut(_ number: Int) -> KeyboardShortcut? {
        BrowserShortcutCommand.spaceSelection(number).flatMap(shortcut)
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
