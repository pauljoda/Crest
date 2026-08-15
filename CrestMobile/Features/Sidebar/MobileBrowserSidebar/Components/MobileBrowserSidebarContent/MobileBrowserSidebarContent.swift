import SwiftUI

struct MobileBrowserSidebarContent: View {
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        if #available(iOS 27.0, *) {
            MobileBrowserSidebarLayout(configuration: configuration)
        } else {
            MobileBrowserSidebarLayout(configuration: configuration)
                .gesture(
                    MobileDragReleaseGesture {
                        configuration.browser.tabDragState.endAfterTouchRelease()
                        configuration.browser.folderDragState.endAfterTouchRelease()
                    }
                )
        }
    }
}

#Preview("Mobile Browser Sidebar Content") {
    @Previewable @Namespace var compactChromeNamespace
    @Previewable @Namespace var tabPromotionNamespace
    @Previewable @State var address = ""
    @Previewable @State var isAddressEditing = false
    @Previewable @State var utilitySearchText = ""
    @Previewable @State var utilityFilter = BrowserUtilityListFilter.all
    let fixture = MobileBrowserSidebarContentPreviewFixture()

    MobileBrowserSidebarContent(
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
