import SwiftUI

/// What the page menus say about automatic pop-ups the page tried to open:
/// a way to allow them for the site, or why that is not offered.
struct MobileBlockedPopupActions: View {
    let notice: BrowserBlockedPopupNotice
    let allow: () -> Void

    var body: some View {
        Section("Automatic Pop-ups") {
            if notice.status.offersAllow {
                Button(action: allow) {
                    Label(
                        "Allow Automatic Pop-ups",
                        systemImage: notice.status.symbol
                    )
                }
                .accessibilityLabel(
                    notice.allowActionAccessibilityLabel
                )
                .accessibilityHint(
                    notice.allowActionAccessibilityHint
                )
                .accessibilityIdentifier("allow-blocked-automatic-popups")
            } else {
                Label(notice.title, systemImage: notice.status.symbol)
                    .accessibilityLabel(
                        Text(verbatim: "\(notice.title). \(notice.guidance)")
                    )
                Text(notice.guidance)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
