import AppKit
import SwiftUI

/// What one command does in the Mac shell: whether it can do it now, what the
/// menu bar calls it and whether it checks it when that follows the window,
/// and what it runs. Each command the core names has exactly one, which the
/// menu bar, its keys and the command palette all run. The core says what a
/// window's contents allow; a command here says what the page and its engine
/// can do.
@MainActor
struct BrowserMacCommand {
    // MARK: - Static Variables

    static let newWindow = BrowserMacCommand(
        .newWindow, withoutWindow: .always { $0.open(.normal(sourceWindowID: nil), activation: .key) },
        run: { $0.openNewWindow() })
    static let newBlankWindow = BrowserMacCommand(.newBlankWindow) { $0.openBlankWindow() }
    static let newTab = BrowserMacCommand(.newTab) { $0.openNewTab() }
    static let openLocation = BrowserMacCommand(.openLocation) { $0.openLocation() }
    static let openFile = BrowserMacCommand(
        .openFile, isAvailable: { $0.supportsEngineCapability(.localFiles) },
        run: { $0.openFile() })
    static let newQuickWindow = BrowserMacCommand(.newQuickWindow) { $0.openQuickWindow() }
    static let newPrivateWindow = BrowserMacCommand(
        .newPrivateWindow, withoutWindow: .always { $0.openPrivateWindow() },
        run: { $0.openPrivateWindow() })
    static let closeTabOrWindow = BrowserMacCommand(
        .closeTabOrWindow, withoutWindow: .closesShellWindow,
        run: { $0.closeTabOrWindow() })
    static let closeWindow = BrowserMacCommand(
        .closeWindow, withoutWindow: .closesShellWindow, run: { $0.closeKeyWindow() })
    static let back = BrowserMacCommand(.back, isAvailable: { $0.pages.canGoBack }, run: { $0.pages.goBack() })
    static let forward = BrowserMacCommand(
        .forward, isAvailable: { $0.pages.canGoForward }, run: { $0.pages.goForward() })
    static let reloadPage = BrowserMacCommand(.reloadPage) { $0.pages.reloadOrStop() }
    static let stopLoading = BrowserMacCommand(
        .stopLoading, isAvailable: { $0.pages.isLoading },
        run: { $0.pages.stopLoading() })
    static let reloadFromOrigin = BrowserMacCommand(.reloadFromOrigin) { $0.pages.reloadFromOrigin() }
    static let toggleSelectedTabPinned = BrowserMacCommand(.toggleSelectedTabPinned) { $0.toggleSelectedTabPinned() }
    static let duplicateTab = BrowserMacCommand(.duplicateTab) { $0.duplicateSelectedTab() }
    static let reopenClosedTab = BrowserMacCommand(.reopenClosedTab) { $0.reopenClosedTab() }
    static let clearUnpinnedTabs = BrowserMacCommand(.clearUnpinnedTabs) { $0.cleanupCurrentTabs() }
    static let archiveTab = BrowserMacCommand(.archiveTab) { $0.archiveSelectedTab() }
    static let previousTab = BrowserMacCommand(.previousTab) { $0.selectPreviousTab() }
    static let nextTab = BrowserMacCommand(.nextTab) { $0.selectNextTab() }
    static let mostRecentTab = BrowserMacCommand(.mostRecentTab) { $0.selectMostRecentTab() }
    static let splitWithNextTab = BrowserMacCommand(.splitWithNextTab) { $0.splitWithNextTab() }
    static let focusNextSplitCard = BrowserMacCommand(.focusNextSplitCard) { $0.focusAdjacentSplitCard(offset: 1) }
    static let focusPreviousSplitCard = BrowserMacCommand(.focusPreviousSplitCard) {
        $0.focusAdjacentSplitCard(offset: -1)
    }
    static let removeTabFromSplit = BrowserMacCommand(.removeTabFromSplit) { $0.removeSelectedTabFromSplit() }
    static let separateSplitTabs = BrowserMacCommand(.separateSplitTabs) { $0.separateSplitTabs() }
    static let moveSplitCardLeft = BrowserMacCommand(
        .moveSplitCardLeft, isAvailable: { $0.canMoveFocusedSplitCard(.left) },
        run: { $0.moveFocusedSplitCard(.left) })
    static let moveSplitCardRight = BrowserMacCommand(
        .moveSplitCardRight, isAvailable: { $0.canMoveFocusedSplitCard(.right) },
        run: { $0.moveFocusedSplitCard(.right) })
    static let previousSpace = BrowserMacCommand(.previousSpace) { $0.selectPreviousSpace() }
    static let nextSpace = BrowserMacCommand(.nextSpace) { $0.selectNextSpace() }
    static let toggleReaderMode = BrowserMacCommand(
        .toggleReaderMode, isAvailable: { $0.supportsPageCapability(.reader) && $0.pages.readerModeState.canToggle },
        title: { $0.pages.readerModeActionTitle }, run: { $0.pages.toggleReaderMode() })
    static let toggleContentBlocking = BrowserMacCommand(
        .toggleContentBlocking, isAvailable: { $0.supportsEngineCapability(.contentBlocking) },
        title: { $0.contentBlockingActionTitle }, run: { $0.toggleContentBlocking() })
    static let findInPage = BrowserMacCommand(
        .findInPage, isAvailable: { $0.supportsPageCapability(.find) },
        run: { $0.pages.presentFind() })
    static let findNext = BrowserMacCommand(
        .findNext, isAvailable: { $0.canFindAgain }, waitsInPaletteUntilAvailable: true,
        run: { $0.pages.findAgain(.forward) })
    static let findPrevious = BrowserMacCommand(
        .findPrevious, isAvailable: { $0.canFindAgain }, waitsInPaletteUntilAvailable: true,
        run: { $0.pages.findAgain(.backward) })
    static let zoomIn = BrowserMacCommand(.zoomIn, isAvailable: { $0.canZoom }, run: { $0.zoomIn() })
    static let zoomOut = BrowserMacCommand(.zoomOut, isAvailable: { $0.canZoom }, run: { $0.zoomOut() })
    static let actualSize = BrowserMacCommand(.actualSize, isAvailable: { $0.canZoom }, run: { $0.resetZoom() })
    static let copyPageLink = BrowserMacCommand(
        .copyPageLink, isAvailable: { $0.pages.hasActivePage },
        run: { $0.copyPageLink() })
    static let copyPageLinkAsMarkdown = BrowserMacCommand(
        .copyPageLinkAsMarkdown, isAvailable: { $0.pages.hasActivePage },
        run: { $0.copyPageLinkAsMarkdown() })
    static let sharePage = BrowserMacCommand(
        .sharePage, isAvailable: { $0.pages.hasActivePage },
        run: { $0.pages.sharePage() })
    static let exportPDF = BrowserMacCommand(
        .exportPDF, isAvailable: { $0.supportsPageCapability(.pdf) },
        run: { $0.pages.exportPDF() })
    static let saveWebArchive = BrowserMacCommand(
        .saveWebArchive, isAvailable: { $0.supportsPageCapability(.webArchive) },
        run: { $0.pages.exportWebArchive() })
    static let printPage = BrowserMacCommand(
        .printPage, isAvailable: { $0.supportsPageCapability(.print) },
        run: { $0.pages.printPage() })
    static let toggleSidebar = BrowserMacCommand(.toggleSidebar) { $0.toggleSidebar() }
    static let showHistory = BrowserMacCommand(.showHistory) { $0.chrome.presentUtility(.history) }
    static let showArchive = BrowserMacCommand(.showArchive) { $0.chrome.presentUtility(.archive) }
    static let showDownloads = BrowserMacCommand(
        .showDownloads, isAvailable: { $0.supportsEngineCapability(.downloads) },
        run: { $0.chrome.presentUtility(.downloads) })
    static let showWebInspector = BrowserMacCommand(
        .showWebInspector, isAvailable: { $0.supportsPageCapability(.inspector) },
        run: { $0.pages.showWebInspector() })
    static let toggleTranslationToolbar = BrowserMacCommand(
        .toggleTranslationToolbar,
        isAvailable: { $0.supportsPageCapability(.translation) && !$0.pages.readerModeState.isActive },
        isOn: { $0.pages.activePage?.translation.showsToolbar == true },
        run: { actions in
            guard let page = actions.pages.activePage, !page.readerModeState.isActive else { return }
            page.translation.toggleToolbarVisibility()
        })
    static let toggleDeveloperToolbar = BrowserMacCommand(
        .toggleDeveloperToolbar, isAvailable: { $0.pages.hasActivePage },
        isOn: { $0.pages.activePage?.isDeveloperModeEnabled == true },
        run: { actions in
            guard let page = actions.pages.activePage else { return }
            page.setDeveloperToolbarVisible(!page.isDeveloperModeEnabled)
        })
    /// ⌘1–⌘9 and ⌃1–⌃9: the stop or Space the core says the number leads to now.
    static let selectNumbered = BrowserMacCommand(
        .selectNumbered, isAvailable: { actions, command in actions.numberedSelections[command] != nil },
        run: { actions, command in
            guard let selection = actions.numberedSelections[command] else { return }
            actions.select(selection)
        })

    /// Every command the Mac shell runs, one for each kind the core names.
    static let all = [
        newWindow, newBlankWindow, newTab, openLocation, openFile, newQuickWindow, newPrivateWindow, closeTabOrWindow,
        closeWindow,
        back, forward, reloadPage, stopLoading, reloadFromOrigin, toggleSelectedTabPinned, duplicateTab,
        reopenClosedTab,
        clearUnpinnedTabs, archiveTab, previousTab, nextTab, mostRecentTab, splitWithNextTab, focusNextSplitCard,
        focusPreviousSplitCard, removeTabFromSplit, separateSplitTabs, moveSplitCardLeft, moveSplitCardRight,
        previousSpace, nextSpace,
        toggleReaderMode, toggleContentBlocking, findInPage, findNext, findPrevious, zoomIn, zoomOut, actualSize,
        copyPageLink,
        copyPageLinkAsMarkdown,
        sharePage, exportPDF, saveWebArchive, printPage, toggleSidebar, showHistory, showArchive, showDownloads,
        showWebInspector,
        toggleTranslationToolbar, toggleDeveloperToolbar, selectNumbered,
    ]

    // MARK: - Variables

    /// The kind of command this runs.
    let kind: ShortcutCommand.Kinds

    /// Whether the window can run the command now, as far as the page and its engine go.
    let isAvailable: @MainActor (BrowserCommandActions, ShortcutCommand) -> Bool

    /// What the menu bar calls the command now, or nil for its own title.
    let title: @MainActor (BrowserCommandActions) -> LocalizedStringResource?

    /// Whether what the command shows or hides is showing, or nil for a command
    /// the menu bar never checks.
    let isOn: @MainActor (BrowserCommandActions) -> Bool?

    /// Runs the command in a window.
    let run: @MainActor (BrowserCommandActions, ShortcutCommand) -> Void

    /// What the command does while no browser window is key, or nil for a
    /// command that needs one.
    let withoutWindow: BrowserMacWindowlessCommand?

    /// Whether the palette lists the command only while it can run, for a
    /// command that means nothing until something else happens first, such
    /// as finding again before any search.
    let waitsInPaletteUntilAvailable: Bool

    // MARK: - Initializers

    private init(
        _ kind: ShortcutCommand.Kinds,
        isAvailable: @escaping @MainActor (BrowserCommandActions) -> Bool = { _ in true },
        title: @escaping @MainActor (BrowserCommandActions) -> LocalizedStringResource? = { _ in nil },
        isOn: @escaping @MainActor (BrowserCommandActions) -> Bool? = { _ in nil },
        withoutWindow: BrowserMacWindowlessCommand? = nil,
        waitsInPaletteUntilAvailable: Bool = false,
        run: @escaping @MainActor (BrowserCommandActions) -> Void
    ) {
        self.init(
            kind, isAvailable: { actions, _ in isAvailable(actions) }, title: title, isOn: isOn,
            withoutWindow: withoutWindow, waitsInPaletteUntilAvailable: waitsInPaletteUntilAvailable,
            run: { actions, _ in run(actions) })
    }

    private init(
        _ kind: ShortcutCommand.Kinds,
        isAvailable: @escaping @MainActor (BrowserCommandActions, ShortcutCommand) -> Bool,
        title: @escaping @MainActor (BrowserCommandActions) -> LocalizedStringResource? = { _ in nil },
        isOn: @escaping @MainActor (BrowserCommandActions) -> Bool? = { _ in nil },
        withoutWindow: BrowserMacWindowlessCommand? = nil,
        waitsInPaletteUntilAvailable: Bool = false,
        run: @escaping @MainActor (BrowserCommandActions, ShortcutCommand) -> Void
    ) {
        self.kind = kind
        self.isAvailable = isAvailable
        self.title = title
        self.isOn = isOn
        self.withoutWindow = withoutWindow
        self.waitsInPaletteUntilAvailable = waitsInPaletteUntilAvailable
        self.run = run
    }

    // MARK: - Actions - Lookup

    /// What `command` does in the Mac shell, or nil for a kind of command the
    /// shell does not run, which it then never offers.
    static func of(_ command: ShortcutCommand) -> BrowserMacCommand? {
        all.first { $0.kind == command.kind }
    }
}

/// What a command does while no browser window is key: a new window opens
/// from nothing, and a window the shell opened, such as a Quick Window or
/// setup, closes itself.
@MainActor
struct BrowserMacWindowlessCommand {
    // MARK: - Static Variables

    /// Closes the key window when it is one the shell opened.
    static let closesShellWindow = BrowserMacWindowlessCommand(
        isAvailable: { $0.isShellWindowKey }, run: { _ in NSApp.keyWindow?.performClose(nil) })

    // MARK: - Variables

    /// Whether the shell's windows can run it now.
    let isAvailable: @MainActor (BrowserMacWindows) -> Bool

    /// Runs it with the shell's windows.
    let run: @MainActor (BrowserMacWindows) -> Void

    // MARK: - Initializers

    /// A command that always runs with the shell's windows.
    static func always(_ run: @escaping @MainActor (BrowserMacWindows) -> Void) -> BrowserMacWindowlessCommand {
        BrowserMacWindowlessCommand(isAvailable: { _ in true }, run: run)
    }
}
