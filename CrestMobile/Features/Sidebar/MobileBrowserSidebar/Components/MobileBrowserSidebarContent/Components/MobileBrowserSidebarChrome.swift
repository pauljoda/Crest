import SwiftUI

struct MobileBrowserSidebarChrome: View {
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        VStack(spacing: 0) {
            MobileBrowserSidebarTopChrome(configuration: configuration)

            MobileSpacePicker(
                browser: configuration.browser,
                pages: configuration.pages,
                spaceAccess: configuration.spaceAccess,
                selectSpace: configuration.selectSpace
            )
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
    }
}

#Preview("Mobile Browser Sidebar Chrome", traits: .sizeThatFitsLayout) {
    @Previewable @Namespace var compactChromeNamespace
    @Previewable @Namespace var tabPromotionNamespace
    @Previewable @State var address = ""
    @Previewable @State var isAddressEditing = false
    @Previewable @State var utilitySearchText = ""
    @Previewable @State var utilityFilter = BrowserUtilityListFilter.all
    let fixture = MobileBrowserSidebarContentPreviewFixture()

    MobileBrowserSidebarChrome(
        configuration: fixture.configuration(
            compactChromeNamespace: compactChromeNamespace,
            tabPromotionNamespace: tabPromotionNamespace,
            address: $address,
            isAddressEditing: $isAddressEditing,
            utilitySearchText: $utilitySearchText,
            utilityFilter: $utilityFilter
        )
    )
}
