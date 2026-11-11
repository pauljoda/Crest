import SwiftUI

/// The search-mode bar's way to the page menu: a round glass button that
/// raises the menu's sheet from the bar, marked when pop-ups were blocked or
/// downloads are new, as the Page Actions button in the address bar is.
struct MobilePageMenuButton: View {
    let pages: any MobilePageActions
    let downloadsAccess: MobileDownloadsMenuAccess?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Image(systemName: "chevron.up")
                .frame(width: CrestLayout.minimumHitTarget, height: CrestLayout.minimumHitTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) { badge }
        .accessibilityLabel(MobilePageActionsMenu.accessibilityLabel(pages: pages, downloadsAccess: downloadsAccess))
        .accessibilityHint(MobilePageActionsMenu.accessibilityHint(pages: pages))
        .accessibilityIdentifier("page-menu-button")
        .modifier(MobilePagePermissionPrompts(pages: pages))
    }

    /// What waits in the menu: new downloads by count, else blocked pop-ups.
    @ViewBuilder
    private var badge: some View {
        if let downloadsAccess, downloadsAccess.newItemCount > 0 {
            BrowserUtilityNotificationBadge(
                count: downloadsAccess.newItemCount,
                tint: .accentColor,
                progress: downloadsAccess.activeProgress
            )
            .offset(x: 4, y: -2)
        } else if pages.blockedPopupNotice != nil {
            Circle()
                .fill(CrestColor.warning)
                .frame(width: 8, height: 8)
                .offset(x: -6, y: 6)
                .accessibilityHidden(true)
        }
    }
}
