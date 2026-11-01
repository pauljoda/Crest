import SwiftUI

/// The latest group notice, as the Space settings list shows it under its
/// Spaces; nothing while there is none.
struct BrowserSpaceGroupNoticeLabel: View {
    var body: some View {
        if let notice = BrowserSpaceGroupNotices.shared.current {
            Label(notice.message, systemImage: notice.systemImage)
                .accessibilityIdentifier("space-group-notice")
        }
    }
}
