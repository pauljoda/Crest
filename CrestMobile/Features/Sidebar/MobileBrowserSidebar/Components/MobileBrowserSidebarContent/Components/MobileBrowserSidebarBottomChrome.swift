import SwiftUI

struct MobileBrowserSidebarBottomChrome: View {
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        switch MobileBrowserSidebarBottomChromePolicy.content(
            for: configuration.mode,
            isVisible: isVisible
        ) {
        case .actions:
            if BrowserSidebarAccessPolicy.showsSelectedSpaceActions(
                in: configuration.browser,
                accessController: configuration.spaceAccess
            ) {
                MobileSpaceActions(
                    browser: configuration.browser,
                    pages: configuration.pages,
                    mode: configuration.mode,
                    configuration: configuration.spaceActionsConfiguration
                )
                .transition(.opacity)
            } else {
                reservedSpace
            }
        case .reservedSpace:
            reservedSpace
        }
    }

    private var reservedSpace: some View {
        Color.clear
            .frame(height: 60)
            .accessibilityHidden(true)
    }

    private var isVisible: Bool {
        configuration.mode == .regularSidebar
            || configuration.showsBottomSpaceSwitcher
    }
}
