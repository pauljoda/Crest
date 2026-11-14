import Foundation

extension BrowserSidebarInteractionState {
    // MARK: - Actions - Link Feedback

    /// Confirms a link or palette row that opened behind the page the person is using.
    func browserDidOpenBackgroundTab() {
        BrowserNoticeCenter.shared.post(.openedInBackgroundTab)
    }

    /// Asks the window's sidebar to bring a tab this window opened into view.
    func browserDidOpenTab(_ tabID: UUID, in spaceID: UUID) {
        revealRequest = BrowserSidebarRevealRequest(tabID: tabID, spaceID: spaceID)
    }
}
