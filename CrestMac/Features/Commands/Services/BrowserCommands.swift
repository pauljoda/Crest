import AppKit
import SwiftUI

struct BrowserCommands: Commands {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let chrome: BrowserChromeState
    let shortcuts: BrowserShortcutStore
    let softwareUpdates: BrowserSoftwareUpdateService
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
                openWindow(id: BrowserSceneID.settings.rawValue)
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
                commandPages.reloadOrStop(in: commandBrowser.session)
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
                commandPages.reloadFromOrigin(in: commandBrowser.session)
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
            ForEach(1...9, id: \.self) { number in
                Button("Select Tab \(number)", systemImage: "\(number).square") {
                    actions.selectTab(at: number - 1)
                }
                .keyboardShortcut(tabSelectionShortcut(number))
                .disabled(number > actions.orderedTabs.count)
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
            ForEach(1...9, id: \.self) { number in
                Button("Select Space \(number)", systemImage: "\(number).square") {
                    actions.selectSpace(at: number - 1)
                }
                .keyboardShortcut(spaceSelectionShortcut(number))
                .disabled(number > commandBrowser.session.spaces.count)
            }
        }

        CommandMenu("Page") {
            Button(
                commandPages.readerModeActionTitle,
                systemImage: BrowserShortcutCommand.toggleReaderMode.paletteSymbol,
                action: commandPages.toggleReaderMode
            )
            .keyboardShortcut(shortcut(.toggleReaderMode))
            .disabled(!commandPages.readerModeState.canToggle)
            Button(
                actions.contentBlockingActionTitle,
                systemImage: BrowserShortcutCommand.toggleContentBlocking.paletteSymbol,
                action: actions.toggleContentBlocking
            )
            .keyboardShortcut(shortcut(.toggleContentBlocking))
            .disabled(commandBrowser.selectedSpace == nil)
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
            .disabled(!commandPages.hasActivePage)
            Button(
                "Zoom Out",
                systemImage: BrowserShortcutCommand.zoomOut.paletteSymbol,
                action: actions.zoomOut
            )
            .keyboardShortcut(shortcut(.zoomOut))
            .disabled(!commandPages.hasActivePage)
            Button(
                "Actual Size",
                systemImage: BrowserShortcutCommand.actualSize.paletteSymbol,
                action: actions.resetZoom
            )
            .keyboardShortcut(shortcut(.actualSize))
            .disabled(!commandPages.hasActivePage)
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
            .disabled(!commandPages.hasActivePage)
            Button(
                "Save Web Archive…",
                systemImage: BrowserShortcutCommand.saveWebArchive.paletteSymbol,
                action: commandPages.exportWebArchive
            )
            .keyboardShortcut(shortcut(.saveWebArchive))
            .disabled(!commandPages.hasActivePage)
        }

        CommandMenu("Develop") {
            Button(
                "Show Web Inspector",
                systemImage: BrowserShortcutCommand.showWebInspector.paletteSymbol,
                action: commandPages.showWebInspector
            )
            .keyboardShortcut(shortcut(.showWebInspector))
            .disabled(!commandPages.hasActivePage)
        }

        CommandGroup(replacing: .printItem) {
            Button(
                "Print…",
                systemImage: BrowserShortcutCommand.printPage.paletteSymbol,
                action: commandPages.printPage
            )
            .keyboardShortcut(shortcut(.printPage))
            .disabled(!commandPages.hasActivePage)
        }

        CommandGroup(after: .sidebar) {
            Button(
                "Toggle Sidebar",
                systemImage: BrowserShortcutCommand.toggleSidebar.paletteSymbol,
                action: actions.toggleSidebar
            )
            .keyboardShortcut(shortcut(.toggleSidebar))
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

    private var actions: BrowserCommandActions {
        BrowserCommandActions(
            browser: commandBrowser,
            pages: commandPages,
            chrome: commandChrome,
            openWindow: openWindow,
            targetWindowID: focusedContext?.windowID,
            layoutDirection: layoutDirection
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
