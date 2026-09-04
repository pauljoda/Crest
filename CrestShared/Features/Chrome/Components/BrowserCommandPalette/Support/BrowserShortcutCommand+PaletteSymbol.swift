extension BrowserShortcutCommand {
    var paletteSymbol: String {
        switch self {
        case .newWindow, .newQuickWindow: "macwindow.badge.plus"
        case .newTab: "plus.square"
        case .newPrivateWindow: "eyeglasses"
        case .closeTabOrWindow, .closeWindow: "xmark.square"
        case .archiveTab: "archivebox"
        case .openLocation: "magnifyingglass"
        case .back: "chevron.left"
        case .forward: "chevron.right"
        case .reloadPage, .reloadFromOrigin: "arrow.clockwise"
        case .stopLoading: "xmark.circle"
        case .toggleSelectedTabPinned: "pin"
        case .duplicateTab: "plus.square.on.square"
        case .reopenClosedTab: "arrow.uturn.backward"
        case .clearUnpinnedTabs: "sparkles"
        case .previousTab, .previousSpace: "chevron.up"
        case .nextTab, .nextSpace: "chevron.down"
        case .mostRecentTab: "arrow.left.arrow.right"
        case .toggleReaderMode: "doc.plaintext"
        case .toggleContentBlocking: "shield"
        case .findInPage: "text.magnifyingglass"
        case .zoomIn: "plus.magnifyingglass"
        case .zoomOut: "minus.magnifyingglass"
        case .actualSize: "1.magnifyingglass"
        case .copyPageLink, .copyPageLinkAsMarkdown: "link"
        case .sharePage: "square.and.arrow.up"
        case .exportPDF, .saveWebArchive: "square.and.arrow.down"
        case .printPage: "printer"
        case .toggleSidebar: "sidebar.leading"
        case .toggleExtensionSidePanel: "sidebar.trailing"
        case .showHistory: "clock"
        case .showArchive: "archivebox"
        case .showDownloads: "arrow.down.circle"
        case .showWebInspector: "hammer"
        case .splitWithNextTab: "rectangle.split.2x1"
        case .focusNextSplitCard: "rectangle.righthalf.filled"
        case .focusPreviousSplitCard: "rectangle.lefthalf.filled"
        case .removeTabFromSplit: "minus.rectangle"
        case .separateSplitTabs: "rectangle.split.2x1.slash"
        // A fixed-direction arrow, not a mirroring `backward`/`forward` one:
        // the command names a side of the screen, and it still names that side
        // in a right-to-left layout.
        case .moveSplitCardLeft: "arrow.left.square"
        case .moveSplitCardRight: "arrow.right.square"
        case .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9:
            "square.on.square"
        case .selectSpace1, .selectSpace2, .selectSpace3, .selectSpace4,
            .selectSpace5, .selectSpace6, .selectSpace7, .selectSpace8,
            .selectSpace9:
            "rectangle.3.group"
        }
    }
}
