import SwiftUI

struct MobilePageHistoryControls: View {
    let pageActions: MobileSelectedPageActionPort?

    /// Opens History from the end of either history menu.
    let showHistory: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let pageActions, pageActions.isAvailable {
                availableHistoryControls(pageActions: pageActions)
            } else {
                historyButton(
                    title: "Back",
                    systemImage: "chevron.left",
                    enabled: false,
                    action: {}
                )
            }
        }
        .animation(
            CrestMotion.navigation.unlessReducingMotion(reduceMotion),
            value: pageActions?.canGoForward == true
        )
    }

    @ViewBuilder
    private func availableHistoryControls(
        pageActions: MobileSelectedPageActionPort
    ) -> some View {
        if pageActions.canGoForward {
            backAndForwardControls(pageActions: pageActions)
        } else {
            backButton(pageActions: pageActions)
                .transition(.opacity)
        }
    }

    private func backAndForwardControls(
        pageActions: MobileSelectedPageActionPort
    ) -> some View {
        HStack(spacing: 0) {
            backButton(pageActions: pageActions, wearsGlass: false)
            Divider()
                .frame(height: MobileBrowserChromeLayout.historyDividerHeight)
                .opacity(MobileBrowserChromeLayout.historyDividerOpacity)
            forwardButton(pageActions: pageActions)
        }
        .padding(
            .horizontal,
            MobileBrowserChromeLayout.historyCapsuleHorizontalPadding
        )
        .crestInteractiveGlass(in: .capsule)
        .transition(.opacity)
    }

    private func backButton(
        pageActions: MobileSelectedPageActionPort,
        wearsGlass: Bool = true
    ) -> some View {
        historyButton(
            title: "Back",
            systemImage: "chevron.left",
            enabled: pageActions.canGoBack,
            wearsGlass: wearsGlass,
            action: pageActions.goBack
        )
        .contextMenu {
            BrowserNavigationHistoryMenu(
                items: pageActions.backHistory,
                emptyTitle: "No Earlier Pages",
                action: pageActions.goBack(to:),
                showFullHistory: showHistory
            )
            .tint(.primary)
        }
    }

    private func forwardButton(
        pageActions: MobileSelectedPageActionPort
    ) -> some View {
        historyButton(
            title: "Forward",
            systemImage: "chevron.right",
            enabled: true,
            wearsGlass: false,
            action: pageActions.goForward
        )
        .contextMenu {
            BrowserNavigationHistoryMenu(
                items: pageActions.forwardHistory,
                emptyTitle: "No Later Pages",
                action: pageActions.goForward(to:),
                showFullHistory: showHistory
            )
            .tint(.primary)
        }
    }

    private func historyButton(
        title: String,
        systemImage: String,
        enabled: Bool,
        wearsGlass: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        MobileCompactIconButton(
            title: title,
            systemImage: systemImage,
            enabled: enabled,
            wearsGlass: wearsGlass,
            action: action
        )
    }
}
