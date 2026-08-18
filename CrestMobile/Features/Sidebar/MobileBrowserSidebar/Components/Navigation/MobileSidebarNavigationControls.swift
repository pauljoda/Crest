import SwiftUI

struct MobileSidebarNavigationControls: View {
    let browser: BrowserStore
    let pageActions: (any MobilePageActions)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 2) {
            Spacer(minLength: 0)

            Button("Back", systemImage: "chevron.left") {
                pageActions?.goBack()
            }
            .disabled(pageActions?.canGoBack != true)
            .foregroundStyle(
                pageActions?.canGoBack == true
                    ? Color.primary
                    : Color.secondary.opacity(CrestOpacity.controlDisabledForeground)
            )
            .font(.system(size: 17, weight: .medium))
            .contextMenu {
                MobileNavigationHistoryMenu(
                    items: pageActions?.backHistory ?? [],
                    emptyTitle: "No Earlier Pages",
                    action: { pageActions?.goBack(to: $0) }
                )
                .tint(.primary)
            }
            if pageActions?.canGoForward == true {
                Button("Forward", systemImage: "chevron.right") {
                    pageActions?.goForward()
                }
                .foregroundStyle(.primary)
                .font(.system(size: 17, weight: .medium))
                .contextMenu {
                    MobileNavigationHistoryMenu(
                        items: pageActions?.forwardHistory ?? [],
                        emptyTitle: "No Later Pages",
                        action: { pageActions?.goForward(to: $0) }
                    )
                    .tint(.primary)
                }
            }

            BrowserReloadControl(
                isLoading: pageActions?.activePage?.isLoading == true,
                isDeveloperMode: BrowserDeveloperModePolicy.isAutomatic(
                    for: pageActions?.activeURL
                ),
                reloadOrStop: { pageActions?.reloadOrStop() },
                reload: { pageActions?.reload() },
                reloadFromOrigin: { pageActions?.reloadFromOrigin() },
                clearSiteDataAndReload: {
                    await pageActions?.clearSiteDataAndReload()
                },
                isEnabled: pageActions?.isAvailable == true,
                menuControlSize: CGSize(width: 28, height: 44)
            )
            if let pageActions, pageActions.isAvailable {
                MobilePageActionsMenu(
                    browser: browser,
                    pages: pageActions,
                    systemImage: "ellipsis.circle"
                )
                .font(.system(size: 17, weight: .medium))
            } else {
                Button("Page Actions", systemImage: "ellipsis.circle", action: {})
                    .disabled(true)
                    .font(.system(size: 17, weight: .medium))
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(
            CrestChromeButtonStyle(
                controlSize: CGSize(width: 44, height: 44)
            )
        )
        .padding(.horizontal, 14)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
        .frame(minHeight: 48)
    }
}
