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

#Preview("Mobile Sidebar Bottom Chrome", traits: .sizeThatFitsLayout) {
    @Previewable @Namespace var compactChromeNamespace
    @Previewable @Namespace var tabPromotionNamespace
    @Previewable @State var address = ""
    @Previewable @State var isAddressEditing = false
    @Previewable @State var utilitySearchText = ""
    @Previewable @State var utilityFilter = BrowserUtilityListFilter.all
    let fixture = MobileBrowserSidebarContentPreviewFixture()

    MobileBrowserSidebarBottomChrome(
        configuration: fixture.configuration(
            compactChromeNamespace: compactChromeNamespace,
            tabPromotionNamespace: tabPromotionNamespace,
            address: $address,
            isAddressEditing: $isAddressEditing,
            utilitySearchText: $utilitySearchText,
            utilityFilter: $utilityFilter,
            mode: .compactTabViewer
        )
    )
}
