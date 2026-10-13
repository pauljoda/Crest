import SwiftUI

extension BrowserCommandActions {
    // MARK: - Variables

    var canFind: Bool {
        canSearchHistory || commandPageSupports(.find)
    }

    private var canSearchHistory: Bool {
        guard chrome.utilityPresentation.surface == .history,
            chrome.columnVisibility != .detailOnly || chrome.isFloatingSidebarPresented,
            let space = browser.shownSpace, !spaceAccess.isLocked(space)
        else { return false }
        return true
    }

    // MARK: - Actions - Find

    func presentFind() {
        if canSearchHistory {
            chrome.utilityPresentation.focusSearch()
        } else {
            pages.commandPage?.presentFind()
        }
    }
}
