import SwiftUI

struct MobileBrowserCommands: Commands {
    let shortcuts: BrowserShortcutStore
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.mobileBrowserCommandContext) private var context

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Window") {
                openWindow(value: BrowserWindowID())
            }
            .keyboardShortcut(shortcut(.newWindow))

            Button("New Tab") {
                context?.openNewTab()
            }
            .keyboardShortcut(shortcut(.newTab))
            .disabled(context == nil)

            Button(context?.isPrivateBrowsing == true ? "Leave Private Browsing" : "Private Browsing") {
                context?.togglePrivateBrowsing()
            }
            .keyboardShortcut(shortcut(.newPrivateWindow))
            .disabled(context == nil)

            Button("Close Tab") {
                context?.dismissSelectedTab()
            }
            .keyboardShortcut(shortcut(.closeTabOrWindow))
            .disabled(context?.canDismissSelectedTab != true)
        }

        CommandMenu("Navigate") {
            Button("Open Location") {
                context?.openLocation()
            }
            .keyboardShortcut(shortcut(.openLocation))
            .disabled(context == nil)

            Divider()

            Button("Back") {
                context?.goBack()
            }
            .keyboardShortcut(shortcut(.back))
            .disabled(context?.canGoBack != true)

            // The arrow and bracket aliases below are second chords for commands
            // the table already carries, and the store holds exactly one binding
            // per command. They stay literal on purpose: a hardware keyboard on
            // iPad expects ⌘←/→ for history the way Safari does, and rebinding
            // "Back" should not take that away.
            Button("Back (Arrow)") {
                context?.goBack()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(context?.canGoBack != true)

            Button("Forward") {
                context?.goForward()
            }
            .keyboardShortcut(shortcut(.forward))
            .disabled(context?.canGoForward != true)

            Button("Forward (Arrow)") {
                context?.goForward()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(context?.canGoForward != true)

            Button("Reload Page") {
                context?.reloadOrStop()
            }
            .keyboardShortcut(shortcut(.reloadPage))
            .disabled(context?.hasActivePage != true)

            Button("Stop Loading") {
                context?.stopLoading()
            }
            .keyboardShortcut(shortcut(.stopLoading))
            .disabled(context?.isLoading != true)

            Button("Reload from Origin") {
                context?.reloadFromOrigin()
            }
            .keyboardShortcut(shortcut(.reloadFromOrigin))
            .disabled(context?.hasActivePage != true)
        }

        CommandMenu("Tabs") {
            Button("Pin or Unpin Tab") {
                context?.toggleSelectedTabPinned()
            }
            .keyboardShortcut(shortcut(.toggleSelectedTabPinned))
            .disabled(context?.hasSelectedTab != true)

            Button("Duplicate Tab") {
                context?.duplicateSelectedTab()
            }
            .keyboardShortcut(shortcut(.duplicateTab))
            .disabled(context?.canDuplicateSelectedTab != true)

            Button("Reopen Closed Tab") {
                context?.reopenClosedTab()
            }
            .keyboardShortcut(shortcut(.reopenClosedTab))
            .disabled(context?.canReopenClosedTab != true)

            Button("Clear Unpinned Tabs") {
                context?.cleanupCurrentTabs()
            }
            .keyboardShortcut(shortcut(.clearUnpinnedTabs))
            .disabled(context == nil)

            Button("Archive Tab") {
                context?.archiveSelectedTab()
            }
            .keyboardShortcut(shortcut(.archiveTab))
            .disabled(context?.canArchiveSelectedTab != true)

            Divider()

            Button("Previous Tab") {
                context?.selectPreviousTab()
            }
            .keyboardShortcut(shortcut(.previousTab))
            .disabled((context?.tabCount ?? 0) < 2)

            Button("Next Tab") {
                context?.selectNextTab()
            }
            .keyboardShortcut(shortcut(.nextTab))
            .disabled((context?.tabCount ?? 0) < 2)

            Button("Previous Tab (Bracket)") {
                context?.selectPreviousTab()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled((context?.tabCount ?? 0) < 2)

            Button("Next Tab (Bracket)") {
                context?.selectNextTab()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled((context?.tabCount ?? 0) < 2)

            Button("Most Recent Tab") {
                context?.selectMostRecentTab()
            }
            .keyboardShortcut(shortcut(.mostRecentTab))
            .disabled((context?.tabCount ?? 0) < 2)

            Divider()

            Button("Split With Next Tab") {
                context?.splitWithNextTab()
            }
            .keyboardShortcut(shortcut(.splitWithNextTab))
            .disabled(context?.canSplitWithNextTab != true)

            Button("Focus Next Split Card") {
                context?.focusNextSplitCard()
            }
            .keyboardShortcut(shortcut(.focusNextSplitCard))
            .disabled(context?.isSelectedTabInSplit != true)

            Button("Focus Previous Split Card") {
                context?.focusPreviousSplitCard()
            }
            .keyboardShortcut(shortcut(.focusPreviousSplitCard))
            .disabled(context?.isSelectedTabInSplit != true)

            Button("Move Split Card Left") {
                context?.moveFocusedSplitCard(.left)
            }
            .keyboardShortcut(shortcut(.moveSplitCardLeft))
            .disabled(context?.canMoveFocusedSplitCard(.left) != true)

            Button("Move Split Card Right") {
                context?.moveFocusedSplitCard(.right)
            }
            .keyboardShortcut(shortcut(.moveSplitCardRight))
            .disabled(context?.canMoveFocusedSplitCard(.right) != true)

            Button("Remove Tab From Split") {
                context?.removeTabFromSplit()
            }
            .keyboardShortcut(shortcut(.removeTabFromSplit))
            .disabled(context?.isSelectedTabInSplit != true)

            Button("Separate All Tabs") {
                context?.separateSplitTabs()
            }
            .keyboardShortcut(shortcut(.separateSplitTabs))
            .disabled(context?.isSelectedTabInSplit != true)

            Divider()

            ForEach(1...9, id: \.self) { number in
                Button("Select Tab \(number)") {
                    context?.selectTab(number - 1)
                }
                .keyboardShortcut(tabSelectionShortcut(number))
                .disabled(number > (context?.tabCount ?? 0))
            }
        }

        CommandMenu("Spaces") {
            Button("Previous Space") {
                context?.selectPreviousSpace()
            }
            .keyboardShortcut(shortcut(.previousSpace))
            .disabled((context?.spaceCount ?? 0) < 2)

            Button("Next Space") {
                context?.selectNextSpace()
            }
            .keyboardShortcut(shortcut(.nextSpace))
            .disabled((context?.spaceCount ?? 0) < 2)

            Divider()

            ForEach(1...9, id: \.self) { number in
                Button("Select Space \(number)") {
                    context?.selectSpace(number - 1)
                }
                .keyboardShortcut(spaceSelectionShortcut(number))
                .disabled(number > (context?.spaceCount ?? 0))
            }
        }

        CommandMenu("Page") {
            Button(context?.readerModeActionTitle ?? "Show Reader") {
                context?.toggleReaderMode()
            }
            .keyboardShortcut(shortcut(.toggleReaderMode))
            .disabled(context?.canToggleReaderMode != true)

            Button(context?.contentBlockingActionTitle ?? "Content Blocking") {
                Task { await context?.toggleContentBlocking() }
            }
            .keyboardShortcut(shortcut(.toggleContentBlocking))
            .disabled(context?.hasActivePage != true)

            Divider()

            Button("Find in Page") {
                context?.presentFind()
            }
            .keyboardShortcut(shortcut(.findInPage))
            .disabled(context?.hasActivePage != true)

            Divider()

            Button("Zoom In") {
                context?.zoomIn()
            }
            .keyboardShortcut(shortcut(.zoomIn))
            .disabled(context?.hasActivePage != true)

            Button("Zoom Out") {
                context?.zoomOut()
            }
            .keyboardShortcut(shortcut(.zoomOut))
            .disabled(context?.hasActivePage != true)

            Button("Actual Size") {
                context?.resetZoom()
            }
            .keyboardShortcut(shortcut(.actualSize))
            .disabled(context?.hasActivePage != true)

            Divider()

            Button("Copy Page Link") {
                context?.copyPageLink()
            }
            .keyboardShortcut(shortcut(.copyPageLink))
            .disabled(context?.hasActivePage != true)

            Button("Copy Page Link as Markdown") {
                context?.copyPageLinkAsMarkdown()
            }
            .keyboardShortcut(shortcut(.copyPageLinkAsMarkdown))
            .disabled(context?.hasActivePage != true)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print…") {
                context?.printPage()
            }
            .keyboardShortcut(shortcut(.printPage))
            .disabled(context?.hasActivePage != true)
        }

        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                context?.toggleSidebar()
            }
            .keyboardShortcut(shortcut(.toggleSidebar))
            .disabled(context == nil)

            Button("Show History") {
                context?.presentHistory()
            }
            .keyboardShortcut(shortcut(.showHistory))
            .disabled(context == nil)

            Button("Show Archive") {
                context?.presentArchive()
            }
            .keyboardShortcut(shortcut(.showArchive))
            .disabled(context == nil)

            Button("Show Downloads") {
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
