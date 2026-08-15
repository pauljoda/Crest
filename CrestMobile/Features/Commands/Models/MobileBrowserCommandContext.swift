import SwiftUI

struct MobileBrowserCommandContext {
    let isPrivateBrowsing: Bool
    let canGoBack: Bool
    let canGoForward: Bool
    let hasSelectedTab: Bool
    let hasActivePage: Bool
    let isLoading: Bool
    let canDismissSelectedTab: Bool
    let canArchiveSelectedTab: Bool
    let canDuplicateSelectedTab: Bool
    let canReopenClosedTab: Bool
    let tabCount: Int
    let spaceCount: Int
    let isSelectedTabInSplit: Bool
    let canSplitWithNextTab: Bool
    /// Which way the cards are laid out, so a command that names a side of the
    /// screen resolves to the right member. See `BrowserSplitCardMoveDirection`.
    let layoutDirection: LayoutDirection
    let readerModeActionTitle: LocalizedStringResource
    let canToggleReaderMode: Bool
    let contentBlockingActionTitle: LocalizedStringResource

    let openNewTab: () -> Void
    let togglePrivateBrowsing: () -> Void
    let openLocation: () -> Void
    let goBack: () -> Void
    let goForward: () -> Void
    let reloadOrStop: () -> Void
    let stopLoading: () -> Void
    let reloadFromOrigin: () -> Void
    let toggleSelectedTabPinned: () -> Void
    let duplicateSelectedTab: () -> Void
    let reopenClosedTab: () -> Void
    let cleanupCurrentTabs: () -> Void
    let dismissSelectedTab: () -> Void
    let archiveSelectedTab: () -> Void
    let selectPreviousTab: () -> Void
    let selectNextTab: () -> Void
    let selectMostRecentTab: () -> Void
    let selectTab: (Int) -> Void
    let splitWithNextTab: () -> Void
    let focusNextSplitCard: () -> Void
    let focusPreviousSplitCard: () -> Void
    let removeTabFromSplit: () -> Void
    let separateSplitTabs: () -> Void
    let canMoveFocusedSplitCard: (Int) -> Bool
    let moveFocusedSplitCard: (Int) -> Void
    let selectPreviousSpace: () -> Void
    let selectNextSpace: () -> Void
    let selectSpace: (Int) -> Void
    let toggleReaderMode: () -> Void
    let toggleContentBlocking: () async -> Void
    let presentFind: () -> Void
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let resetZoom: () -> Void
    let copyPageLink: () -> Void
    let copyPageLinkAsMarkdown: () -> Void
    let printPage: () -> Void
    let toggleSidebar: () -> Void
    let presentHistory: () -> Void
    let presentArchive: () -> Void
    let presentDownloads: () -> Void
}
