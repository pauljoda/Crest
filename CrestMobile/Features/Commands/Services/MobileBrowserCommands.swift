import SwiftUI

struct MobileBrowserCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.mobileBrowserCommandContext) private var context

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Window") {
                openWindow(value: BrowserWindowID())
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Tab") {
                context?.openNewTab()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(context == nil)

            Button(context?.isPrivateBrowsing == true ? "Leave Private Browsing" : "Private Browsing") {
                context?.togglePrivateBrowsing()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(context == nil)

            Button("Close Tab") {
                context?.dismissSelectedTab()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(context?.canDismissSelectedTab != true)
        }

        CommandMenu("Navigate") {
            Button("Open Location") {
                context?.openLocation()
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(context == nil)

            Divider()

            Button("Back") {
                context?.goBack()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(context?.canGoBack != true)

            Button("Back (Arrow)") {
                context?.goBack()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(context?.canGoBack != true)

            Button("Forward") {
                context?.goForward()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(context?.canGoForward != true)

            Button("Forward (Arrow)") {
                context?.goForward()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(context?.canGoForward != true)

            Button("Reload Page") {
                context?.reloadOrStop()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(context?.hasActivePage != true)

            Button("Stop Loading") {
                context?.stopLoading()
            }
            .keyboardShortcut(
                MobileBrowserKeyboardShortcut.stopLoadingKey,
                modifiers: MobileBrowserKeyboardShortcut.stopLoadingModifiers
            )
            .disabled(context?.isLoading != true)

            Button("Reload from Origin") {
                context?.reloadFromOrigin()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(context?.hasActivePage != true)
        }

        CommandMenu("Tabs") {
            Button("Pin or Unpin Tab") {
                context?.toggleSelectedTabPinned()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(context?.hasSelectedTab != true)

            Button("Duplicate Tab") {
                context?.duplicateSelectedTab()
            }
            .disabled(context?.canDuplicateSelectedTab != true)

            Button("Reopen Closed Tab") {
                context?.reopenClosedTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(context?.canReopenClosedTab != true)

            Button("Clear Unpinned Tabs") {
                context?.cleanupCurrentTabs()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(context == nil)

            Button("Archive Tab") {
                context?.archiveSelectedTab()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(context?.canArchiveSelectedTab != true)

            Divider()

            Button("Previous Tab") {
                context?.selectPreviousTab()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled((context?.tabCount ?? 0) < 2)

            Button("Next Tab") {
                context?.selectNextTab()
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
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
            .keyboardShortcut(KeyEquivalent("\t"), modifiers: .control)
            .disabled((context?.tabCount ?? 0) < 2)

            Divider()

            // Same chords as macOS, hardcoded the way every other shortcut in
            // this file is: iPadOS has no rebinding surface yet, so the shared
            // default policy has nothing to resolve against here.
            Button("Split With Next Tab") {
                context?.splitWithNextTab()
            }
            .disabled(context?.canSplitWithNextTab != true)

            Button("Focus Next Split Card") {
                context?.focusNextSplitCard()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.control, .command])
            .disabled(context?.isSelectedTabInSplit != true)

            Button("Focus Previous Split Card") {
                context?.focusPreviousSplitCard()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.control, .command])
            .disabled(context?.isSelectedTabInSplit != true)

            Button("Move Split Card Left") {
                context?.moveFocusedSplitCard(.left)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
            .disabled(context?.canMoveFocusedSplitCard(.left) != true)

            Button("Move Split Card Right") {
                context?.moveFocusedSplitCard(.right)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
            .disabled(context?.canMoveFocusedSplitCard(.right) != true)

            Button("Remove Tab From Split") {
                context?.removeTabFromSplit()
            }
            .disabled(context?.isSelectedTabInSplit != true)

            Button("Separate All Tabs") {
                context?.separateSplitTabs()
            }
            .keyboardShortcut("u", modifiers: [.command, .option])
            .disabled(context?.isSelectedTabInSplit != true)

            Divider()

            ForEach(1...9, id: \.self) { number in
                Button("Select Tab \(number)") {
                    context?.selectTab(number - 1)
                }
                .keyboardShortcut(
                    KeyEquivalent(Character(String(number))),
                    modifiers: .command
                )
                .disabled(number > (context?.tabCount ?? 0))
            }
        }

        CommandMenu("Spaces") {
            Button("Previous Space") {
                context?.selectPreviousSpace()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled((context?.spaceCount ?? 0) < 2)

            Button("Next Space") {
                context?.selectNextSpace()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled((context?.spaceCount ?? 0) < 2)

            Divider()

            ForEach(1...9, id: \.self) { number in
                Button("Select Space \(number)") {
                    context?.selectSpace(number - 1)
                }
                .keyboardShortcut(
                    KeyEquivalent(Character(String(number))),
                    modifiers: .control
                )
                .disabled(number > (context?.spaceCount ?? 0))
            }
        }

        CommandMenu("Page") {
            Button(context?.readerModeActionTitle ?? "Show Reader") {
                context?.toggleReaderMode()
            }
            .disabled(context?.canToggleReaderMode != true)

            Button(context?.contentBlockingActionTitle ?? "Content Blocking") {
                Task { await context?.toggleContentBlocking() }
            }
            .disabled(context?.hasActivePage != true)

            Divider()

            Button("Find in Page") {
                context?.presentFind()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(context?.hasActivePage != true)

            Divider()

            Button("Zoom In") {
                context?.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(context?.hasActivePage != true)

            Button("Zoom Out") {
                context?.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(context?.hasActivePage != true)

            Button("Actual Size") {
                context?.resetZoom()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(context?.hasActivePage != true)

            Divider()

            Button("Copy Page Link") {
                context?.copyPageLink()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(context?.hasActivePage != true)

            Button("Copy Page Link as Markdown") {
                context?.copyPageLinkAsMarkdown()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift, .option])
            .disabled(context?.hasActivePage != true)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print…") {
                context?.printPage()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(context?.hasActivePage != true)
        }

        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                context?.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(context == nil)

            Button("Show History") {
                context?.presentHistory()
            }
            .keyboardShortcut("y", modifiers: .command)
            .disabled(context == nil)

            Button("Show Archive") {
                context?.presentArchive()
            }
            .disabled(context == nil)

            Button("Show Downloads") {
                context?.presentDownloads()
            }
            .keyboardShortcut(
                MobileBrowserKeyboardShortcut.downloadsKey,
                modifiers: MobileBrowserKeyboardShortcut.downloadsModifiers
            )
            .disabled(context == nil)
        }
    }
}
