import SwiftUI

extension MobileBrowserCommandContext {
    /// The commands the launcher offers on iOS and iPadOS.
    ///
    /// It is the Mac list minus everything the platform has no answer for:
    /// extra window kinds, the Web Inspector, and the share and export sheets,
    /// none of which this shell implements. A command absent here simply never
    /// appears in the launcher — that is the whole contract.
    static let paletteCommands: [BrowserShortcutCommand] = [
        .closeTabOrWindow,
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
        .printPage,
        .toggleSidebar,
        .showHistory,
        .showArchive,
        .showDownloads,
    ]

    /// The on-screen direction resolved against this shell's layout, so the
    /// hardware-keyboard menu and the launcher ask the same question.
    func canMoveFocusedSplitCard(
        _ direction: BrowserSplitCardMoveDirection
    ) -> Bool {
        canMoveFocusedSplitCard(
            direction.memberOffset(layoutDirection: layoutDirection)
        )
    }

    func moveFocusedSplitCard(_ direction: BrowserSplitCardMoveDirection) {
        moveFocusedSplitCard(
            direction.memberOffset(layoutDirection: layoutDirection)
        )
    }

    /// iPadOS does not let a reader rebind these yet, so the launcher shows the
    /// command names without chords.
    @MainActor
    var paletteRegistry: BrowserCommandPaletteCommandRegistry {
        BrowserCommandPaletteCommandRegistry(
            commands: Self.paletteCommands,
            perform: performFromPalette
        )
    }

    @MainActor
    private func performFromPalette(_ command: BrowserShortcutCommand) {
        switch command {
        case .closeTabOrWindow: dismissSelectedTab()
        case .archiveTab: archiveSelectedTab()
        case .back: goBack()
        case .forward: goForward()
        case .reloadPage: reloadOrStop()
        case .stopLoading: stopLoading()
        case .reloadFromOrigin: reloadFromOrigin()
        case .toggleSelectedTabPinned: toggleSelectedTabPinned()
        case .duplicateTab: duplicateSelectedTab()
        case .reopenClosedTab: reopenClosedTab()
        case .clearUnpinnedTabs: cleanupCurrentTabs()
        case .previousTab: selectPreviousTab()
        case .nextTab: selectNextTab()
        case .mostRecentTab: selectMostRecentTab()
        case .splitWithNextTab: splitWithNextTab()
        case .focusNextSplitCard: focusNextSplitCard()
        case .focusPreviousSplitCard: focusPreviousSplitCard()
        case .removeTabFromSplit: removeTabFromSplit()
        case .separateSplitTabs: separateSplitTabs()
        case .moveSplitCardLeft: moveFocusedSplitCard(.left)
        case .moveSplitCardRight: moveFocusedSplitCard(.right)
        case .previousSpace: selectPreviousSpace()
        case .nextSpace: selectNextSpace()
        case .toggleReaderMode: toggleReaderMode()
        case .toggleContentBlocking:
            Task { await toggleContentBlocking() }
        case .findInPage: presentFind()
        case .zoomIn: zoomIn()
        case .zoomOut: zoomOut()
        case .actualSize: resetZoom()
        case .copyPageLink: copyPageLink()
        case .copyPageLinkAsMarkdown: copyPageLinkAsMarkdown()
        case .printPage: printPage()
        case .toggleSidebar: toggleSidebar()
        case .showHistory: presentHistory()
        case .showArchive: presentArchive()
        case .showDownloads: presentDownloads()
        default:
            // Everything else is deliberately unregistered on this platform, so
            // the launcher never offers it and this arm never runs.
            break
        }
    }
}
