import SwiftUI

struct MobilePageActionsMenu: View {
    let browser: BrowserStore
    let pages: any MobilePageActions
    let systemImage: String
    var downloadsAccess: MobileDownloadsMenuAccess? = nil
    var hideToolbar: (() -> Void)? = nil
    var controlSize = CGSize(width: 44, height: 44)

    var body: some View {
        Menu {
            MobilePageActionsContent(
                browser: browser,
                pages: pages,
                downloadsAccess: downloadsAccess,
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
                if let downloadsAccess, downloadsAccess.newItemCount > 0 {
                    BrowserUtilityNotificationBadge(
                        count: downloadsAccess.newItemCount,
                        tint: .accentColor,
                        progress: downloadsAccess.activeProgress
                    )
                    .offset(x: 9, y: -7)
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
        var label =
            pages.blockedPopupNotice?.chromeAccessibilityLabel(
                surfaceName: "Page Actions"
            ) ?? "Page Actions"
        if let downloadsAccess, downloadsAccess.newItemCount > 0 {
            label += ", \(downloadsAccess.unreadAccessibilityValue)"
        }
        return label
    }

    private var accessibilityHint: String {
        guard pages.blockedPopupNotice != nil else {
            return "Opens controls for this webpage"
        }
        return "Opens the Automatic Pop-ups permission and retry guidance"
    }
}

struct MobileDownloadsMenuAccess {
    let newItemCount: Int
    let activeProgress: Double?
    let open: @MainActor () -> Void

    var rowTitle: String {
        guard newItemCount > 0 else {
            return String(localized: "Downloads")
        }
        return String(localized: "Downloads (\(newItemCount))")
    }

    var unreadAccessibilityValue: String {
        BrowserChromeAccessibility.countValue(
            newItemCount,
            singular: "new download",
            plural: "new downloads"
        )
    }
}
