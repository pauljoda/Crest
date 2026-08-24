import SwiftUI

struct BrowserBlockedPopupSiteControlNotice: View {
    let notice: BrowserBlockedPopupNotice
    let allow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.small) {
            Label(notice.title, systemImage: symbol)
                .font(.caption.weight(.semibold))

            Text(notice.guidance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if notice.status == .blocked {
                Button("Allow Automatic Pop-ups") {
                    allow()
                }
                .buttonStyle(.crestPrimary)
                .controlSize(.small)
                .accessibilityLabel(
                    notice.allowActionAccessibilityLabel
                )
                .accessibilityHint(
                    notice.allowActionAccessibilityHint
                )
                .accessibilityIdentifier("allow-blocked-automatic-popups")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CrestSpacing.small)
        .background(.quaternary, in: .rect(cornerRadius: CrestRadius.control))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(notice.title)
        .accessibilityIdentifier("blocked-popup-site-control-notice")
    }

    private var symbol: String {
        switch notice.status {
        case .blocked:
            "macwindow.badge.plus"
        case .allowedAwaitingRetry:
            "checkmark.circle"
        }
    }
}
