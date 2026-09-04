enum BrowserShortcutDefaultPolicy {
    static func shortcut(
        for command: BrowserShortcutCommand
    ) -> BrowserShortcut? {
        if let number = BrowserShortcutNumberedSelectionPolicy.tabNumber(
            for: command
        ) {
            return character(Character(String(number)), [.command])
        }
        if let number = BrowserShortcutNumberedSelectionPolicy.spaceNumber(
            for: command
        ) {
            return character(Character(String(number)), [.control])
        }

        return switch command {
        case .newWindow: character("n", [.command])
        case .newTab: character("t", [.command])
        case .newQuickWindow: character("n", [.command, .option])
        case .newPrivateWindow: character("n", [.command, .shift])
        case .closeTabOrWindow: character("w", [.command])
        case .closeWindow: character("w", [.command, .shift])
        case .openLocation: character("l", [.command])
        case .back: character("[", [.command])
        case .forward: character("]", [.command])
        case .reloadPage: character("r", [.command])
        case .stopLoading: character(".", [.command])
        case .reloadFromOrigin: character("r", [.command, .shift])
        case .toggleSelectedTabPinned: character("d", [.command])
        case .duplicateTab: nil
        case .reopenClosedTab: character("t", [.command, .shift])
        case .clearUnpinnedTabs: character("k", [.command, .shift])
        case .archiveTab: character("e", [.command])
        case .previousTab: special(.upArrow, [.command, .option])
        case .nextTab: special(.downArrow, [.command, .option])
        case .mostRecentTab: special(.tab, [.control])
        case .previousSpace: special(.leftArrow, [.command, .option])
        case .nextSpace: special(.rightArrow, [.command, .option])
        case .toggleReaderMode: nil
        case .toggleContentBlocking: nil
        case .findInPage: character("f", [.command])
        case .zoomIn: character("+", [.command])
        case .zoomOut: character("-", [.command])
        case .actualSize: character("0", [.command])
        case .copyPageLink: character("c", [.command, .shift])
        case .copyPageLinkAsMarkdown:
            character("c", [.command, .option, .shift])
        case .sharePage, .exportPDF, .saveWebArchive: nil
        case .printPage: character("p", [.command])
        case .toggleSidebar: character("s", [.command])
        case .toggleExtensionSidePanel: nil
        case .showHistory: character("y", [.command])
        case .showArchive: nil
        case .showDownloads: character("j", [.command, .shift])
        case .showWebInspector: character("i", [.command, .option])
        // Zen ships ⌥⌘U for unsplit-all, and ⌃⌘←/→ is the one arrow pair the
        // catalog leaves free: ⌥⌘←/→ already switches Spaces and ⌥⌘↑/↓ tabs.
        // Splitting and un-splitting a single card stay menu-and-palette only —
        // Arc's ⌘⇧+ collides with `zoomIn` on ANSI layouts, and ⌘W already
        // closes the focused card because the focused card is the selected tab.
        case .splitWithNextTab: nil
        case .focusNextSplitCard: special(.rightArrow, [.control, .command])
        case .focusPreviousSplitCard: special(.leftArrow, [.control, .command])
        case .removeTabFromSplit: nil
        case .separateSplitTabs: character("u", [.command, .option])
        // ⇧⌘←/→ is the last arrow pair the table leaves free, once ⌥⌘ arrows
        // (Spaces and tabs) and ⌃⌘ arrows (split focus) are spoken for. It does
        // shadow the system's extend-selection-to-line-edge while a text field
        // has the insertion point — which is why the menu items carrying it are
        // disabled unless a split is actually on screen, and why they are
        // rebindable like everything else here.
        case .moveSplitCardLeft: special(.leftArrow, [.command, .shift])
        case .moveSplitCardRight: special(.rightArrow, [.command, .shift])
        case .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9,
            .selectSpace1, .selectSpace2, .selectSpace3, .selectSpace4,
            .selectSpace5, .selectSpace6, .selectSpace7, .selectSpace8,
            .selectSpace9:
            preconditionFailure("Numbered shortcuts resolve before this switch")
        }
    }
    private static func character(
        _ character: Character,
        _ modifiers: BrowserShortcutModifiers
    ) -> BrowserShortcut {
        BrowserShortcut(key: .character(character), modifiers: modifiers)
    }

    private static func special(
        _ key: BrowserShortcutSpecialKey,
        _ modifiers: BrowserShortcutModifiers
    ) -> BrowserShortcut {
        BrowserShortcut(key: .special(key), modifiers: modifiers)
    }
}
