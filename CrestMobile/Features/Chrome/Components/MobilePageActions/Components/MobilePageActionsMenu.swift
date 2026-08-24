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
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: controlSize.width, height: controlSize.height)
                .contentShape(.rect)
        }
        .crestMenuActionLabelStyle()
        .tint(.primary)
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Page Actions")
        .accessibilityHint("Opens controls for this webpage")
        .accessibilityIdentifier("page-actions-menu")
    }
}
