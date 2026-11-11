import SwiftUI

struct MobilePageActionsMenu: View {
    let browser: BrowserStore
    let pages: any MobilePageActions
    let systemImage: String
    var downloadsAccess: MobileDownloadsMenuAccess? = nil
    var hideToolbar: (() -> Void)? = nil
    var controlSize = CGSize(width: 44, height: 44)
    /// Whether the menu is a toolbar item, whose label the system draws so a
    /// side toolbar can stand it on end with the others.
    var isToolbarItem = false

    /// Where the menu's control sits in the window.
    @State private var frame: CGRect?

    var body: some View {
        if isToolbarItem {
            menu {
                Label("Page Actions", systemImage: systemImage)
            }
            .badge(downloadsAccess?.newItemCount ?? 0)
        } else {
            menu {
                chromeLabel
            }
            .crestMenuActionLabelStyle()
            .tint(.primary)
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
    }

    private func menu(@ViewBuilder label: () -> some View) -> some View {
        Menu {
            MobilePageActionsContent(
                browser: browser,
                pages: pages,
                downloadsAccess: downloadsAccess,
                hideToolbar: hideToolbar,
                source: frame
            )
            .crestMenuActionLabelStyle()
        } label: {
            label()
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            self.frame = frame
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier("page-actions-menu")
        .modifier(MobilePagePermissionPrompts(pages: pages))
    }

    private var chromeLabel: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    pages.blockedPopupNotice == nil
                        ? Color.secondary
                        : CrestColor.warning
                )
            if pages.blockedPopupNotice != nil {
                Circle()
                    .fill(CrestColor.warning)
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

    private var accessibilityLabel: String {
        Self.accessibilityLabel(pages: pages, downloadsAccess: downloadsAccess)
    }

    private var accessibilityHint: String {
        Self.accessibilityHint(pages: pages)
    }

    /// What VoiceOver reads for a control that opens the page's actions,
    /// with what waits there: blocked pop-ups and new downloads.
    static func accessibilityLabel(pages: any MobilePageActions, downloadsAccess: MobileDownloadsMenuAccess?) -> String
    {
        var label =
            pages.blockedPopupNotice?.chromeAccessibilityLabel(
                surfaceName: "Page Actions"
            ) ?? "Page Actions"
        if let downloadsAccess, downloadsAccess.newItemCount > 0 {
            label += ", \(downloadsAccess.unreadAccessibilityValue)"
        }
        return label
    }

    static func accessibilityHint(pages: any MobilePageActions) -> String {
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
