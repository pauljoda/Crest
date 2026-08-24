import SwiftUI

struct MobilePageActionsMenu: View {
    let browser: BrowserStore
    let pages: any MobilePageActions
    let systemImage: String
    var hideToolbar: (() -> Void)? = nil
    var controlSize = CGSize(width: 44, height: 44)

    var body: some View {
        Menu {
            MobilePageActionsContent(
                browser: browser,
                pages: pages,
                hideToolbar: hideToolbar
            )
            .crestMenuActionLabelStyle()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        pages.blockedPopupNotice == nil
                            ? Color.secondary
                            : Color.orange
                    )
                if pages.blockedPopupNotice != nil {
                    Circle()
                        .fill(.orange)
                        .frame(width: 7, height: 7)
                        .offset(x: 3, y: -3)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: controlSize.width, height: controlSize.height)
            .contentShape(.rect)
        }
        .crestMenuActionLabelStyle()
        .tint(.primary)
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier("page-actions-menu")
    }

    private var accessibilityLabel: String {
        guard let notice = pages.blockedPopupNotice else { return "Page Actions" }
        return notice.chromeAccessibilityLabel(surfaceName: "Page Actions")
    }

    private var accessibilityHint: String {
        guard pages.blockedPopupNotice != nil else {
            return "Opens controls for this webpage"
        }
        return "Opens the Automatic Pop-ups permission and retry guidance"
    }
}
