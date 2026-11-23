import SwiftUI

struct MobilePageActionsMenu: View {
    /// The dot that says a pop-up was blocked, at the glyph's top trailing
    /// corner.
    private static let noticeDotSize: CGFloat = 7
    private static let noticeDotOffset = CGSize(width: 3, height: -3)
    /// Where the new downloads badge sits over the glyph's top trailing
    /// corner.
    private static let badgeOffset = CGSize(width: 9, height: -7)

    let browser: BrowserStore
    let pages: MobileSelectedPageActionPort
    let systemImage: String
    var downloadsAccess: MobileDownloadsMenuAccess? = nil
    var hideToolbar: (() -> Void)? = nil
    var controlSize = CGSize(width: CrestLayout.minimumHitTarget, height: CrestLayout.minimumHitTarget)
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
        .accessibilityIdentifier(BrowserMobileAccessibilityID.pageActionsMenu)
        .pagePermissionHost(pages.activePage?.sitePermissionRequests)
        .crestPopover(
            item: Binding {
                pages.activePage?.sitePermissionRequests.current
            } set: { request in
                if request == nil && pages.activePage?.sitePermissionRequests.current != nil {
                    pages.activePage?.sitePermissionRequests.cancelAll()
                }
            }
        ) { request in
            if let controller = pages.activePage?.sitePermissionRequests {
                BrowserPagePermissionPrompt(request: request, controller: controller)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    private var chromeLabel: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemImage)
                .font(CrestTypography.compactControlGlyph)
                .foregroundStyle(
                    pages.blockedPopupNotice == nil
                        ? Color.secondary
                        : CrestColor.warning
                )
            if pages.blockedPopupNotice != nil {
                Circle()
                    .fill(CrestColor.warning)
                    .frame(width: Self.noticeDotSize, height: Self.noticeDotSize)
                    .offset(Self.noticeDotOffset)
                    .accessibilityHidden(true)
            }
            if let downloadsAccess, downloadsAccess.newItemCount > 0 {
                BrowserUtilityNotificationBadge(
                    count: downloadsAccess.newItemCount,
                    tint: CrestBrandTheme.accent,
                    progress: downloadsAccess.activeProgress
                )
                .offset(Self.badgeOffset)
            }
        }
        .frame(width: controlSize.width, height: controlSize.height)
        .contentShape(.rect)
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
