import Foundation

extension BrowserSidebarInteractionState {
    // MARK: - Actions - Link Feedback

    /// Confirms a modified link that opened behind the page the person is using.
    func browserDidOpenBackgroundTab() {
        BrowserNoticeCenter.shared.post(
            BrowserNotice(message: String(localized: "Opened in Background Tab"), systemImage: "plus.square.on.square"))
    }
}
