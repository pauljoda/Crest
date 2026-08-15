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
            Button("Check for Updates…") {
                softwareUpdates.checkForUpdates()
            }
            .disabled(!softwareUpdates.isEnabled)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openWindow(id: BrowserSceneID.settings.rawValue)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .newItem) {
            Button("New Window", action: actions.openNewWindow)
                .keyboardShortcut(shortcut(.newWindow))
            Button("New Tab", action: actions.openNewTab)
                .keyboardShortcut(shortcut(.newTab))
            Button("New Quick Window", action: actions.openQuickWindow)
                .keyboardShortcut(shortcut(.newQuickWindow))
            Button("New Private Window", action: actions.openPrivateWindow)
                .keyboardShortcut(shortcut(.newPrivateWindow))
            Divider()
            Button("Close Current Tab or Window", action: closeTabOrWindow)
                .keyboardShortcut(shortcut(.closeTabOrWindow))
            Button("Close Window", action: actions.closeKeyWindow)
                .keyboardShortcut(shortcut(.closeWindow))
        }

        CommandMenu("Navigate") {
            Button("Open Location", action: actions.openLocation)
                .keyboardShortcut(shortcut(.openLocation))
            Divider()
            Button("Back", action: commandPages.goBack)
                .keyboardShortcut(shortcut(.back))
                .disabled(!commandPages.canGoBack)
            Button("Forward", action: commandPages.goForward)
                .keyboardShortcut(shortcut(.forward))
                .disabled(!commandPages.canGoForward)
            Button("Reload Page") {
                commandPages.reloadOrStop(in: commandBrowser.session)
            }
            .keyboardShortcut(shortcut(.reloadPage))
            .disabled(!actions.canReloadSelectedTab)
            Button("Stop Loading", action: commandPages.stopLoading)
                .keyboardShortcut(shortcut(.stopLoading))
                .disabled(!commandPages.isLoading)
            Button("Reload from Origin") {
                commandPages.reloadFromOrigin(in: commandBrowser.session)
            }
            .keyboardShortcut(shortcut(.reloadFromOrigin))
            .disabled(!actions.canReloadSelectedTab)
        }

        CommandMenu("Tabs") {
            Button("Pin or Unpin Tab", action: actions.toggleSelectedTabPinned)
                .keyboardShortcut(shortcut(.toggleSelectedTabPinned))
                .disabled(commandBrowser.selectedTab == nil)
            Button("Duplicate Tab", action: actions.duplicateSelectedTab)
                .keyboardShortcut(shortcut(.duplicateTab))
                .disabled(!actions.canDuplicateSelectedTab)
            Button("Reopen Closed Tab", action: actions.reopenClosedTab)
                .keyboardShortcut(shortcut(.reopenClosedTab))
                .disabled(commandBrowser.selectedSpace?.archivedTabs.isEmpty != false)
            Button("Clear Unpinned Tabs", action: actions.cleanupCurrentTabs)
                .keyboardShortcut(shortcut(.clearUnpinnedTabs))
            Button("Archive Tab", action: actions.archiveSelectedTab)
                .keyboardShortcut(shortcut(.archiveTab))
                .disabled(!actions.canArchiveSelectedTab)
            Divider()
            Button("Previous Tab", action: actions.selectPreviousTab)
                .keyboardShortcut(shortcut(.previousTab))
            Button("Next Tab", action: actions.selectNextTab)
                .keyboardShortcut(shortcut(.nextTab))
            Button("Most Recent Tab", action: actions.selectMostRecentTab)
                .keyboardShortcut(shortcut(.mostRecentTab))

            Divider()
            Button("Split With Next Tab", action: actions.splitWithNextTab)
                .keyboardShortcut(shortcut(.splitWithNextTab))
                .disabled(!actions.canSplitWithNextTab)
            Button("Focus Next Split Card") {
                actions.focusAdjacentSplitCard(offset: 1)
            }
            .keyboardShortcut(shortcut(.focusNextSplitCard))
            .disabled(!actions.isSelectedTabInSplit)
            Button("Focus Previous Split Card") {
                actions.focusAdjacentSplitCard(offset: -1)
            }
            .keyboardShortcut(shortcut(.focusPreviousSplitCard))
            .disabled(!actions.isSelectedTabInSplit)
            Button("Move Split Card Left") {
                actions.moveFocusedSplitCard(.left)
            }
            .keyboardShortcut(shortcut(.moveSplitCardLeft))
            .disabled(!actions.canMoveFocusedSplitCard(.left))
            Button("Move Split Card Right") {
                actions.moveFocusedSplitCard(.right)
            }
            .keyboardShortcut(shortcut(.moveSplitCardRight))
            .disabled(!actions.canMoveFocusedSplitCard(.right))
            Button("Remove Tab From Split", action: actions.removeSelectedTabFromSplit)
                .keyboardShortcut(shortcut(.removeTabFromSplit))
                .disabled(!actions.isSelectedTabInSplit)
            Button("Separate All Tabs", action: actions.separateSplitTabs)
                .keyboardShortcut(shortcut(.separateSplitTabs))
                .disabled(!actions.isSelectedTabInSplit)

            Divider()
            ForEach(1...9, id: \.self) { number in
                Button("Select Tab \(number)") {
                    actions.selectTab(at: number - 1)
                }
                .keyboardShortcut(tabSelectionShortcut(number))
                .disabled(number > actions.orderedTabs.count)
            }
        }

        CommandMenu("Spaces") {
            Button("Previous Space", action: actions.selectPreviousSpace)
                .keyboardShortcut(shortcut(.previousSpace))
            Button("Next Space", action: actions.selectNextSpace)
                .keyboardShortcut(shortcut(.nextSpace))
            Divider()
            ForEach(1...9, id: \.self) { number in
                Button("Select Space \(number)") {
                    actions.selectSpace(at: number - 1)
                }
                .keyboardShortcut(spaceSelectionShortcut(number))
                .disabled(number > commandBrowser.session.spaces.count)
            }
        }

        CommandMenu("Page") {
            Button(commandPages.readerModeActionTitle, action: commandPages.toggleReaderMode)
                .keyboardShortcut(shortcut(.toggleReaderMode))
                .disabled(!commandPages.readerModeState.canToggle)
            Button(actions.contentBlockingActionTitle, action: actions.toggleContentBlocking)
                .keyboardShortcut(shortcut(.toggleContentBlocking))
                .disabled(commandBrowser.selectedSpace == nil)
            Divider()
            Button("Find in Page", action: commandPages.presentFind)
                .keyboardShortcut(shortcut(.findInPage))
                .disabled(!commandPages.hasActivePage)
            Divider()
            Button("Zoom In", action: actions.zoomIn)
                .keyboardShortcut(shortcut(.zoomIn))
                .disabled(!commandPages.hasActivePage)
            Button("Zoom Out", action: actions.zoomOut)
                .keyboardShortcut(shortcut(.zoomOut))
                .disabled(!commandPages.hasActivePage)
            Button("Actual Size", action: actions.resetZoom)
                .keyboardShortcut(shortcut(.actualSize))
                .disabled(!commandPages.hasActivePage)
            Divider()
            Button("Copy Page Link", action: actions.copyPageLink)
                .keyboardShortcut(shortcut(.copyPageLink))
                .disabled(!commandPages.hasActivePage)
            Button("Copy Page Link as Markdown", action: actions.copyPageLinkAsMarkdown)
                .keyboardShortcut(shortcut(.copyPageLinkAsMarkdown))
                .disabled(!commandPages.hasActivePage)
            Button("Share…", action: commandPages.sharePage)
                .keyboardShortcut(shortcut(.sharePage))
                .disabled(!commandPages.hasActivePage)
            Button("Export as PDF…", action: commandPages.exportPDF)
                .keyboardShortcut(shortcut(.exportPDF))
                .disabled(!commandPages.hasActivePage)
            Button("Save Web Archive…", action: commandPages.exportWebArchive)
                .keyboardShortcut(shortcut(.saveWebArchive))
                .disabled(!commandPages.hasActivePage)
        }

        CommandMenu("Develop") {
            Button("Show Web Inspector", action: commandPages.showWebInspector)
                .keyboardShortcut(shortcut(.showWebInspector))
                .disabled(!commandPages.hasActivePage)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print…", action: commandPages.printPage)
                .keyboardShortcut(shortcut(.printPage))
                .disabled(!commandPages.hasActivePage)
        }

        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar", action: actions.toggleSidebar)
                .keyboardShortcut(shortcut(.toggleSidebar))
        }

        CommandGroup(after: .toolbar) {
            Button("Show History", action: commandChrome.presentHistory)
                .keyboardShortcut(shortcut(.showHistory))
            Button("Show Archive", action: actions.presentArchive)
                .keyboardShortcut(shortcut(.showArchive))
                .disabled(commandBrowser.selectedSpace == nil)
            Button("Show Downloads", action: actions.presentDownloads)
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
