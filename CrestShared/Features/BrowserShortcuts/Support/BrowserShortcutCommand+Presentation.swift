import Foundation

extension BrowserShortcutCommand {
    var titleResource: LocalizedStringResource {
        if let number = tabNumber {
            return "Select Tab \(number)"
        }
        if let number = spaceNumber {
            return "Select Space \(number)"
        }

        return switch self {
        case .newWindow: "New Window"
        case .newTab: "New Tab"
        case .newQuickWindow: "New Quick Window"
        case .newPrivateWindow: "New Private Window"
        case .closeTabOrWindow: "Close Current Tab or Window"
        case .closeWindow: "Close Window"
        case .openLocation: "Open Location"
        case .back: "Back"
        case .forward: "Forward"
        case .reloadPage: "Reload Page"
        case .stopLoading: "Stop Loading"
        case .reloadFromOrigin: "Reload from Origin"
        case .toggleSelectedTabPinned: "Pin or Unpin Current Tab"
        case .duplicateTab: "Duplicate Tab"
        case .reopenClosedTab: "Reopen Last Closed Tab"
        case .clearUnpinnedTabs: "Clear Unpinned Tabs"
        case .archiveTab: "Archive Tab"
        case .previousTab: "Previous Tab"
        case .nextTab: "Next Tab"
        case .mostRecentTab: "Most Recent Tab"
        case .previousSpace: "Previous Space"
        case .nextSpace: "Next Space"
        case .toggleReaderMode: "Show or Hide Reader"
        case .toggleContentBlocking: "Toggle Content Blocking"
        case .findInPage: "Find in Page"
        case .zoomIn: "Zoom In"
        case .zoomOut: "Zoom Out"
        case .actualSize: "Actual Size"
        case .copyPageLink: "Copy Page Link"
        case .copyPageLinkAsMarkdown: "Copy Page Link as Markdown"
        case .sharePage: "Share Page"
        case .exportPDF: "Export as PDF"
        case .saveWebArchive: "Save Web Archive"
        case .printPage: "Print Page"
        case .toggleSidebar: "Show or Hide Sidebar"
        case .showHistory: "Show History"
        case .showArchive: "Show Archive"
        case .showDownloads: "Show Downloads"
        case .showWebInspector: "Show Web Inspector"
        case .splitWithNextTab: "Split With Next Tab"
        case .focusNextSplitCard: "Focus Next Split Card"
        case .focusPreviousSplitCard: "Focus Previous Split Card"
        case .removeTabFromSplit: "Remove Tab From Split"
        case .separateSplitTabs: "Separate All Tabs"
        case .moveSplitCardLeft: "Move Split Card Left"
        case .moveSplitCardRight: "Move Split Card Right"
        case .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5,
            .selectTab6, .selectTab7, .selectTab8, .selectTab9,
            .selectSpace1, .selectSpace2, .selectSpace3, .selectSpace4,
            .selectSpace5, .selectSpace6, .selectSpace7, .selectSpace8,
            .selectSpace9:
            preconditionFailure("Numbered shortcuts resolve before this switch")
        }
    }

    var title: String {
        title()
    }

    func title(locale: Locale = .current) -> String {
        BrowserShortcutLocalization.string(titleResource, locale: locale)
    }

    func matches(search query: String) -> Bool {
        BrowserShortcutPresentationCatalog().matches(
            self,
            currentShortcut: defaultShortcut,
            query: query
        )
    }

    func matches(
        search query: String,
        currentShortcut: BrowserShortcut?
    ) -> Bool {
        BrowserShortcutPresentationCatalog().matches(
            self,
            currentShortcut: currentShortcut,
            query: query
        )
    }

    var relatedSearchTermsResource: LocalizedStringResource {
        switch self {
        case .copyPageLink: "copy url address clipboard"
        case .copyPageLinkAsMarkdown: "copy url address markdown clipboard"
        case .openLocation: "change current tab url address focus"
        case .closeTabOrWindow: "close archive current tab window"
        case .clearUnpinnedTabs: "clean tidy archive unpinned tabs"
        case .mostRecentTab: "toggle recent switch tabs"
        case .previousTab, .nextTab: "switch cycle tabs up down arrow"
        case .previousSpace, .nextSpace:
            "switch cycle spaces left right arrow"
        case .toggleSelectedTabPinned: "favorite bookmark pin unpin"
        case .newPrivateWindow: "incognito private browsing"
        case .newQuickWindow: "little arc quick lookup"
        case .showHistory: "visited pages history"
        case .showArchive: "closed tabs archive"
        case .showDownloads: "download files transfers"
        case .toggleReaderMode: "reader reading mode"
        case .toggleContentBlocking: "ads trackers privacy protection"
        case .actualSize: "reset zoom zero"
        case .showWebInspector:
            "developer tools inspect element webkit safari"
        case .splitWithNextTab: "split view cards side by side columns"
        case .focusNextSplitCard, .focusPreviousSplitCard:
            "split view cards focus cycle left right arrow"
        case .removeTabFromSplit: "split view card remove leave unsplit"
        case .separateSplitTabs: "split view break up unsplit separate cards"
        case .moveSplitCardLeft, .moveSplitCardRight:
            "split view cards move reorder rearrange left right arrow"
        default: ""
        }
    }
}
