import SwiftUI

struct MobileBrowserSidebarLayout: View {
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        if BrowserSidebarAccessPolicy.availableSpaces(
            in: configuration.browser
        ).isEmpty {
            ContentUnavailableView("No Spaces", systemImage: "square.grid.2x2")
        } else {
            MobileBrowserSidebarBottomChromeLayout(configuration: configuration) {
                MobileBrowserSidebarPager(configuration: configuration)
            }
        }
    }
}

#Preview("Mobile Browser Sidebar Layout") {
    @Previewable @Namespace var compactChromeNamespace
    @Previewable @Namespace var tabPromotionNamespace
    @Previewable @State var address = ""
    @Previewable @State var isAddressEditing = false
    @Previewable @State var utilitySearchText = ""
    @Previewable @State var utilityFilter = BrowserUtilityListFilter.all
    let fixture = MobileBrowserSidebarContentPreviewFixture()

    MobileBrowserSidebarLayout(
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
