import SwiftUI

struct MobileBrowserCommands: Commands {
    let shortcuts: BrowserShortcutStore
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.mobileBrowserCommandContext) private var context

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(
                "New Window",
                systemImage: BrowserShortcutCommand.newWindow.paletteSymbol
            ) {
                openWindow(value: BrowserWindowID())
            }
            .keyboardShortcut(shortcut(.newWindow))

            Button(
                "New Tab",
                systemImage: BrowserShortcutCommand.newTab.paletteSymbol
            ) {
                context?.openNewTab()
            }
            .keyboardShortcut(shortcut(.newTab))
            .disabled(context == nil)

            Button(
                context?.isPrivateBrowsing == true
                    ? "Leave Private Browsing" : "Private Browsing",
                systemImage: BrowserShortcutCommand.newPrivateWindow.paletteSymbol
            ) {
                context?.togglePrivateBrowsing()
            }
            .keyboardShortcut(shortcut(.newPrivateWindow))
            .disabled(context == nil)

            Button(
                "Close Tab",
                systemImage: BrowserShortcutCommand.closeTabOrWindow.paletteSymbol
            ) {
                context?.dismissSelectedTab()
            }
            .keyboardShortcut(shortcut(.closeTabOrWindow))
            .disabled(context?.canDismissSelectedTab != true)
        }

        CommandMenu("Navigate") {
            Button(
                "Open Location",
                systemImage: BrowserShortcutCommand.openLocation.paletteSymbol
            ) {
                context?.openLocation()
            }
            .keyboardShortcut(shortcut(.openLocation))
            .disabled(context == nil)

            Divider()

            Button(
                "Back",
                systemImage: BrowserShortcutCommand.back.paletteSymbol
            ) {
                context?.goBack()
            }
            .keyboardShortcut(shortcut(.back))
            .disabled(context?.canGoBack != true)

            // The arrow and bracket aliases below are second chords for commands
            // the table already carries, and the store holds exactly one binding
            // per command. They stay literal on purpose: a hardware keyboard on
            // iPad expects ⌘←/→ for history the way Safari does, and rebinding
            // "Back" should not take that away.
            Button(
                "Back (Arrow)",
                systemImage: BrowserShortcutCommand.back.paletteSymbol
            ) {
                context?.goBack()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(context?.canGoBack != true)

            Button(
                "Forward",
                systemImage: BrowserShortcutCommand.forward.paletteSymbol
            ) {
                context?.goForward()
            }
            .keyboardShortcut(shortcut(.forward))
            .disabled(context?.canGoForward != true)

            Button(
                "Forward (Arrow)",
                systemImage: BrowserShortcutCommand.forward.paletteSymbol
            ) {
                context?.goForward()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(context?.canGoForward != true)

            Button(
                "Reload Page",
                systemImage: BrowserShortcutCommand.reloadPage.paletteSymbol
            ) {
                context?.reloadOrStop()
            }
            .keyboardShortcut(shortcut(.reloadPage))
            .disabled(context?.hasActivePage != true)

            Button(
                "Stop Loading",
                systemImage: BrowserShortcutCommand.stopLoading.paletteSymbol
            ) {
                context?.stopLoading()
            }
            .keyboardShortcut(shortcut(.stopLoading))
            .disabled(context?.isLoading != true)

            Button(
                "Reload from Origin",
                systemImage: BrowserShortcutCommand.reloadFromOrigin.paletteSymbol
            ) {
                context?.reloadFromOrigin()
            }
            .keyboardShortcut(shortcut(.reloadFromOrigin))
            .disabled(context?.hasActivePage != true)
        }

        CommandMenu("Tabs") {
            Button(
                "Pin or Unpin Tab",
                systemImage: BrowserShortcutCommand.toggleSelectedTabPinned.paletteSymbol
            ) {
                context?.toggleSelectedTabPinned()
            }
            .keyboardShortcut(shortcut(.toggleSelectedTabPinned))
            .disabled(context?.hasSelectedTab != true)

            Button(
                "Duplicate Tab",
                systemImage: BrowserShortcutCommand.duplicateTab.paletteSymbol
            ) {
                context?.duplicateSelectedTab()
            }
            .keyboardShortcut(shortcut(.duplicateTab))
            .disabled(context?.canDuplicateSelectedTab != true)

            Button(
                "Reopen Closed Tab",
                systemImage: BrowserShortcutCommand.reopenClosedTab.paletteSymbol
            ) {
                context?.reopenClosedTab()
            }
            .keyboardShortcut(shortcut(.reopenClosedTab))
            .disabled(context?.canReopenClosedTab != true)

            Button(
                "Clear Unpinned Tabs",
                systemImage: BrowserShortcutCommand.clearUnpinnedTabs.paletteSymbol
            ) {
                context?.cleanupCurrentTabs()
            }
            .keyboardShortcut(shortcut(.clearUnpinnedTabs))
            .disabled(context == nil)

            Button(
                "Archive Tab",
                systemImage: BrowserShortcutCommand.archiveTab.paletteSymbol
            ) {
                context?.archiveSelectedTab()
            }
            .keyboardShortcut(shortcut(.archiveTab))
            .disabled(context?.canArchiveSelectedTab != true)

            Divider()

            Button(
                "Previous Tab",
                systemImage: BrowserShortcutCommand.previousTab.paletteSymbol
            ) {
                context?.selectPreviousTab()
            }
            .keyboardShortcut(shortcut(.previousTab))
            .disabled((context?.tabCount ?? 0) < 2)

            Button(
                "Next Tab",
                systemImage: BrowserShortcutCommand.nextTab.paletteSymbol
            ) {
                context?.selectNextTab()
            }
            .keyboardShortcut(shortcut(.nextTab))
            .disabled((context?.tabCount ?? 0) < 2)

            Button(
                "Previous Tab (Bracket)",
                systemImage: BrowserShortcutCommand.previousTab.paletteSymbol
            ) {
                context?.selectPreviousTab()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled((context?.tabCount ?? 0) < 2)

            Button(
                "Next Tab (Bracket)",
                systemImage: BrowserShortcutCommand.nextTab.paletteSymbol
            ) {
                context?.selectNextTab()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled((context?.tabCount ?? 0) < 2)

            Button(
                "Most Recent Tab",
                systemImage: BrowserShortcutCommand.mostRecentTab.paletteSymbol
            ) {
                context?.selectMostRecentTab()
            }
            .keyboardShortcut(shortcut(.mostRecentTab))
            .disabled((context?.tabCount ?? 0) < 2)

            Divider()

            Button(
                "Split With Next Tab",
                systemImage: BrowserShortcutCommand.splitWithNextTab.paletteSymbol
            ) {
                context?.splitWithNextTab()
            }
            .keyboardShortcut(shortcut(.splitWithNextTab))
            .disabled(context?.canSplitWithNextTab != true)

            Button(
                "Focus Next Split Card",
                systemImage: BrowserShortcutCommand.focusNextSplitCard.paletteSymbol
            ) {
                context?.focusNextSplitCard()
            }
            .keyboardShortcut(shortcut(.focusNextSplitCard))
            .disabled(context?.isSelectedTabInSplit != true)

            Button(
                "Focus Previous Split Card",
                systemImage: BrowserShortcutCommand.focusPreviousSplitCard.paletteSymbol
            ) {
                context?.focusPreviousSplitCard()
            }
            .keyboardShortcut(shortcut(.focusPreviousSplitCard))
            .disabled(context?.isSelectedTabInSplit != true)

            Button(
                "Move Split Card Left",
                systemImage: BrowserShortcutCommand.moveSplitCardLeft.paletteSymbol
            ) {
                context?.moveFocusedSplitCard(.left)
            }
            .keyboardShortcut(shortcut(.moveSplitCardLeft))
            .disabled(context?.canMoveFocusedSplitCard(.left) != true)

            Button(
                "Move Split Card Right",
                systemImage: BrowserShortcutCommand.moveSplitCardRight.paletteSymbol
            ) {
                context?.moveFocusedSplitCard(.right)
            }
            .keyboardShortcut(shortcut(.moveSplitCardRight))
            .disabled(context?.canMoveFocusedSplitCard(.right) != true)

            Button(
                "Remove Tab From Split",
                systemImage: BrowserShortcutCommand.removeTabFromSplit.paletteSymbol
            ) {
                context?.removeTabFromSplit()
            }
            .keyboardShortcut(shortcut(.removeTabFromSplit))
            .disabled(context?.isSelectedTabInSplit != true)

            Button(
                "Separate All Tabs",
                systemImage: BrowserShortcutCommand.separateSplitTabs.paletteSymbol
            ) {
                context?.separateSplitTabs()
            }
            .keyboardShortcut(shortcut(.separateSplitTabs))
            .disabled(context?.isSelectedTabInSplit != true)

            Divider()

            ForEach(1...9, id: \.self) { number in
                Button("Select Tab \(number)", systemImage: "\(number).square") {
                    context?.selectTab(number - 1)
                }
                .keyboardShortcut(tabSelectionShortcut(number))
                .disabled(number > (context?.tabCount ?? 0))
            }
        }

        CommandMenu("Spaces") {
            Button(
                "Previous Space",
                systemImage: BrowserShortcutCommand.previousSpace.paletteSymbol
            ) {
                context?.selectPreviousSpace()
            }
            .keyboardShortcut(shortcut(.previousSpace))
            .disabled((context?.spaceCount ?? 0) < 2)

            Button(
                "Next Space",
                systemImage: BrowserShortcutCommand.nextSpace.paletteSymbol
            ) {
                context?.selectNextSpace()
            }
            .keyboardShortcut(shortcut(.nextSpace))
            .disabled((context?.spaceCount ?? 0) < 2)

            Divider()

            ForEach(1...9, id: \.self) { number in
                Button("Select Space \(number)", systemImage: "\(number).square") {
                    context?.selectSpace(number - 1)
                }
                .keyboardShortcut(spaceSelectionShortcut(number))
                .disabled(number > (context?.spaceCount ?? 0))
            }
        }

        CommandMenu("Page") {
            Button(
                context?.readerModeActionTitle ?? "Show Reader",
                systemImage: BrowserShortcutCommand.toggleReaderMode.paletteSymbol
            ) {
                context?.toggleReaderMode()
            }
            .keyboardShortcut(shortcut(.toggleReaderMode))
            .disabled(context?.canToggleReaderMode != true)

            Button(
                context?.contentBlockingActionTitle ?? "Content Blocking",
                systemImage: BrowserShortcutCommand.toggleContentBlocking.paletteSymbol
            ) {
                Task { await context?.toggleContentBlocking() }
            }
            .keyboardShortcut(shortcut(.toggleContentBlocking))
            .disabled(context?.hasActivePage != true)

            Divider()

            Button(
                "Find in Page",
                systemImage: BrowserShortcutCommand.findInPage.paletteSymbol
            ) {
                context?.presentFind()
            }
            .keyboardShortcut(shortcut(.findInPage))
            .disabled(context?.hasActivePage != true)

            Divider()

            Button(
                "Zoom In",
                systemImage: BrowserShortcutCommand.zoomIn.paletteSymbol
            ) {
                context?.zoomIn()
            }
            .keyboardShortcut(shortcut(.zoomIn))
            .disabled(context?.hasActivePage != true)

            Button(
                "Zoom Out",
                systemImage: BrowserShortcutCommand.zoomOut.paletteSymbol
            ) {
                context?.zoomOut()
            }
            .keyboardShortcut(shortcut(.zoomOut))
            .disabled(context?.hasActivePage != true)

            Button(
                "Actual Size",
                systemImage: BrowserShortcutCommand.actualSize.paletteSymbol
            ) {
                context?.resetZoom()
            }
            .keyboardShortcut(shortcut(.actualSize))
            .disabled(context?.hasActivePage != true)

            Divider()

            Button(
                "Copy Page Link",
                systemImage: BrowserShortcutCommand.copyPageLink.paletteSymbol
            ) {
                context?.copyPageLink()
            }
            .keyboardShortcut(shortcut(.copyPageLink))
            .disabled(context?.hasActivePage != true)

            Button(
                "Copy Page Link as Markdown",
                systemImage: BrowserShortcutCommand.copyPageLinkAsMarkdown.paletteSymbol
            ) {
                context?.copyPageLinkAsMarkdown()
            }
            .keyboardShortcut(shortcut(.copyPageLinkAsMarkdown))
            .disabled(context?.hasActivePage != true)
        }

        CommandGroup(replacing: .printItem) {
            Button(
                "Print…",
                systemImage: BrowserShortcutCommand.printPage.paletteSymbol
            ) {
                context?.printPage()
            }
            .keyboardShortcut(shortcut(.printPage))
            .disabled(context?.hasActivePage != true)
        }

        CommandGroup(after: .sidebar) {
            Button(
                "Toggle Sidebar",
                systemImage: BrowserShortcutCommand.toggleSidebar.paletteSymbol
            ) {
                context?.toggleSidebar()
            }
            .keyboardShortcut(shortcut(.toggleSidebar))
            .disabled(context == nil)

            Button(
                "Show History",
                systemImage: BrowserShortcutCommand.showHistory.paletteSymbol
            ) {
                context?.presentHistory()
            }
            .keyboardShortcut(shortcut(.showHistory))
            .disabled(context == nil)

            Button(
                "Show Archive",
                systemImage: BrowserShortcutCommand.showArchive.paletteSymbol
            ) {
                context?.presentArchive()
            }
            .keyboardShortcut(shortcut(.showArchive))
            .disabled(context == nil)

            Button(
                "Show Downloads",
                systemImage: BrowserShortcutCommand.showDownloads.paletteSymbol
            ) {
                context?.presentDownloads()
            }
            .keyboardShortcut(shortcut(.showDownloads))
            .disabled(context == nil)
        }
    }

    private func shortcut(
        _ command: BrowserShortcutCommand
    ) -> KeyboardShortcut? {
        shortcuts.keyboardShortcut(for: command)
    }

    private func tabSelectionShortcut(_ number: Int) -> KeyboardShortcut? {
        BrowserShortcutCommand.tabSelection(number).flatMap(shortcut)
    }

    private func spaceSelectionShortcut(_ number: Int) -> KeyboardShortcut? {
        BrowserShortcutCommand.spaceSelection(number).flatMap(shortcut)
    }
}
