import SwiftUI

struct SidebarNavigationControls: View {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let sidebarToggleAction: BrowserSidebarToggleAction
    let toggleSidebar: () -> Void

    var body: some View {
        let controlSize = BrowserChromeLayout.sidebarNavigationControlHitTarget
        let symbolPointSize = BrowserChromeLayout.sidebarNavigationSymbolPointSize

        HStack(spacing: BrowserSidebarMetrics.navigationControlSpacing) {
            Color.clear
                .frame(width: BrowserChromeLayout.windowControlsReservedWidth)

            Button(action: toggleSidebar) {
                BrowserChromeSymbolLabel(
                    systemName: "sidebar.left",
                    pointSize: symbolPointSize
                )
                .offset(y: BrowserChromeLayout.sidebarToggleSymbolOffsetY)
            }
            .padding(.leading, BrowserChromeLayout.sidebarToggleLeadingInset)
            .accessibilityLabel(sidebarToggleAction.title)
            .accessibilityIdentifier("browser-sidebar-toggle")
            .help(sidebarToggleAction.title)

            Spacer(minLength: CrestSpacing.small)

            Button(action: pages.goBack) {
                BrowserChromeSymbolLabel(
                    systemName: "chevron.left",
                    pointSize: symbolPointSize
                )
            }
            .accessibilityLabel("Back")
            .accessibilityIdentifier("browser-back-control")
            .disabled(!pages.canGoBack)
            .help("Back (⌘[)")
            .contextMenu {
                BrowserNavigationHistoryMenu(
                    items: pages.backHistory,
                    emptyTitle: "No Earlier Pages",
                    action: pages.goBack(to:)
                )
                .tint(.primary)
            }

            Button(action: pages.goForward) {
                BrowserChromeSymbolLabel(
                    systemName: "chevron.right",
                    pointSize: symbolPointSize
                )
            }
            .accessibilityLabel("Forward")
            .accessibilityIdentifier("browser-forward-control")
            .disabled(!pages.canGoForward)
            .help("Forward (⌘])")
            .contextMenu {
                BrowserNavigationHistoryMenu(
                    items: pages.forwardHistory,
                    emptyTitle: "No Later Pages",
                    action: pages.goForward(to:)
                )
                .tint(.primary)
            }

            BrowserReloadControl(
                isLoading: pages.activePage?.isLoading == true,
                isDeveloperMode: BrowserDeveloperModePolicy.isAutomatic(
                    for: pages.activePage?.displayURL
                ),
                reloadOrStop: { pages.reloadOrStop(in: browser.session) },
                reload: { pages.forceReload(in: browser.session) },
                reloadFromOrigin: { pages.reloadFromOrigin(in: browser.session) },
                clearSiteDataAndReload: pages.clearSiteDataAndReload,
                isEnabled: pages.activePage != nil,
                reloadControlSize: CGSize(
                    width: controlSize,
                    height: controlSize
                ),
                menuControlSize: CGSize(
                    width: BrowserSidebarMetrics.reloadMenuControlWidth,
                    height: controlSize
                ),
                symbolPointSize: symbolPointSize
            )

        }
        .labelStyle(.iconOnly)
        .buttonStyle(
            CrestChromeButtonStyle(
                controlSize: CGSize(
                    width: controlSize,
                    height: controlSize
                )
            )
        )
        .padding(.trailing, BrowserChromeLayout.sidebarNavigationTrailingInset)
        .frame(height: BrowserChromeLayout.sidebarTitlebarHeight)
    }
}

#Preview("Sidebar Navigation Controls") {
    SidebarNavigationControls(
        browser: BrowserSidebarPreviewFixture.makeBrowser(),
        pages: BrowserSidebarPreviewFixture.makePages(),
        sidebarToggleAction: .hide,
        toggleSidebar: {}
    )
    .frame(width: BrowserChromeLayout.sidebarIdealWidth)
}
