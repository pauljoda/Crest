import SwiftUI

extension BrowserCommandActions {
    // MARK: - Variables

    /// History can accept Find even when its window has no page supporting text search.
    var canFind: Bool {
        canSearchHistory || commandPageSupports(.find)
    }

    /// Search is available only in this window's visible History and an unlocked Space.
    private var canSearchHistory: Bool {
        guard chrome.utilityPresentation.surface == .history,
            chrome.columnVisibility != .detailOnly || chrome.isFloatingSidebarPresented,
            let space = browser.shownSpace, !spaceAccess.isLocked(space)
        else { return false }
        return true
    }

    // MARK: - Actions - Find

    /// Routes native Find input to eligible History search, otherwise to the command page.
    func presentFind() {
        if canSearchHistory {
            chrome.utilityPresentation.focusSearch()
        } else {
            pages.commandPage?.presentFind()
        }
    }
}
