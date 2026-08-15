import SwiftUI

struct MobileBrowserSidebarPager: View {
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        ZStack {
            if configuration.mode == .compactTabViewer {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
            }

            BrowserSpacePager(
                spaces: BrowserSidebarAccessPolicy.availableSpaces(
                    in: configuration.browser
                ),
                selectedSpaceID: configuration.browser.session.selectedSpaceID,
                isInteractionLocked: configuration.browser.tabDragState.item != nil
                    || configuration.browser.folderDragState.item != nil,
                selectSpace: configuration.selectSpace,
                settledSpace: configuration.settleSpaceSelection
            ) { space, isSelected in
                MobileBrowserSidebarSpaceSurface(
                    configuration: configuration,
                    space: space,
                    isSelected: isSelected
                )
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                MobileBrowserSidebarChrome(configuration: configuration)
            }
        }
    }
}

#Preview("Mobile Browser Sidebar Pager") {
    @Previewable @Namespace var compactChromeNamespace
    @Previewable @Namespace var tabPromotionNamespace
    @Previewable @State var address = ""
    @Previewable @State var isAddressEditing = false
    @Previewable @State var utilitySearchText = ""
    @Previewable @State var utilityFilter = BrowserUtilityListFilter.all
    let fixture = MobileBrowserSidebarContentPreviewFixture()

    MobileBrowserSidebarPager(
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
