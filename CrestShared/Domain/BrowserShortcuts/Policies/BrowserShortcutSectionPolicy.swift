enum BrowserShortcutSectionPolicy {
    static func section(
        for command: BrowserShortcutCommand
    ) -> BrowserShortcutSection {
        switch command {
        case .newWindow, .newTab, .newQuickWindow, .newPrivateWindow,
            .closeTabOrWindow, .closeWindow, .openLocation, .back, .forward,
            .reloadPage, .stopLoading, .reloadFromOrigin:
            .everyday
        case .toggleSelectedTabPinned, .duplicateTab, .reopenClosedTab,
            .clearUnpinnedTabs, .archiveTab, .previousTab, .nextTab,
            .mostRecentTab, .selectTab1, .selectTab2, .selectTab3,
            .selectTab4, .selectTab5, .selectTab6, .selectTab7,
            .selectTab8, .selectTab9, .splitWithNextTab,
            .focusNextSplitCard, .focusPreviousSplitCard,
            .removeTabFromSplit, .separateSplitTabs,
            .moveSplitCardLeft, .moveSplitCardRight:
            .tabs
        case .previousSpace, .nextSpace, .selectSpace1, .selectSpace2,
            .selectSpace3, .selectSpace4, .selectSpace5, .selectSpace6,
            .selectSpace7, .selectSpace8, .selectSpace9:
            .spaces
        case .toggleReaderMode, .toggleContentBlocking, .findInPage,
            .zoomIn, .zoomOut, .actualSize, .copyPageLink,
            .copyPageLinkAsMarkdown, .sharePage, .exportPDF,
            .saveWebArchive, .printPage:
            .page
        case .toggleSidebar, .showHistory, .showArchive, .showDownloads,
            .showWebInspector:
            .view
        }
    }
}
