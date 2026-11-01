import Foundation

/// The notices a group change shows in the window the person looks at.
@MainActor
enum BrowserSpaceGroupNotices {
    /// A Space joined a group: the first group on this device reminds the
    /// person to update Crest on their other devices.
    static func formed() {
        guard BrowserSpaceGroupUpdateNotice.takeIfDue() else { return }
        BrowserNoticeCenter.shared.post(
            BrowserNotice(message: BrowserSpaceGroupUpdateNotice.message, systemImage: "arrow.down.circle"))
    }

    /// The change could not run: `reason` says why.
    static func failed(_ reason: String) {
        BrowserNoticeCenter.shared.post(BrowserNotice(message: reason, systemImage: "exclamationmark.triangle.fill"))
    }
}
