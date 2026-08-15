import SwiftUI

struct MobileBrowserSidebarBottomChromeLayout<Content: View>: View {
    let configuration: MobileBrowserSidebarContentConfiguration
    let content: Content

    init(
        configuration: MobileBrowserSidebarContentConfiguration,
        @ViewBuilder content: () -> Content
    ) {
        self.configuration = configuration
        self.content = content()
    }

    var body: some View {
        switch MobileBrowserSidebarBottomChromePolicy.placement(
            for: configuration.mode,
            isVisible: configuration.mode == .regularSidebar
                || configuration.showsBottomSpaceSwitcher
        ) {
        case .hidden:
            content
        case .inlineSafeAreaInset:
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    MobileBrowserSidebarBottomChrome(
                        configuration: configuration
                    )
                }
        }
    }
}

#Preview("Mobile Sidebar Bottom Chrome Layout") {
    @Previewable @Namespace var compactChromeNamespace
    @Previewable @Namespace var tabPromotionNamespace
    @Previewable @State var address = ""
    @Previewable @State var isAddressEditing = false
    @Previewable @State var utilitySearchText = ""
    @Previewable @State var utilityFilter = BrowserUtilityListFilter.all
    let fixture = MobileBrowserSidebarContentPreviewFixture()

    MobileBrowserSidebarBottomChromeLayout(
        configuration: fixture.configuration(
            compactChromeNamespace: compactChromeNamespace,
            tabPromotionNamespace: tabPromotionNamespace,
            address: $address,
            isAddressEditing: $isAddressEditing,
            utilitySearchText: $utilitySearchText,
            utilityFilter: $utilityFilter,
            mode: .compactTabViewer
        )
    ) {
        Color.indigo.opacity(0.12)
    }
}
