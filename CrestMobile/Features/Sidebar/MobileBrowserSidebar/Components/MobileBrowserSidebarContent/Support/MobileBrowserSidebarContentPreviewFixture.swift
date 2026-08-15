import SwiftUI

@MainActor
struct MobileBrowserSidebarContentPreviewFixture {
    let browserFixture = MobileBrowserSidebarPreviewFixture()
    let utilityPresentation = BrowserUtilityPresentationState()

    func configuration(
        compactChromeNamespace: Namespace.ID,
        tabPromotionNamespace: Namespace.ID,
        address: Binding<String>,
        isAddressEditing: Binding<Bool>,
        utilitySearchText: Binding<String>,
        utilityFilter: Binding<BrowserUtilityListFilter>,
        mode: MobileBrowserSidebarMode = .regularSidebar
    ) -> MobileBrowserSidebarContentConfiguration {
        MobileBrowserSidebarContentConfiguration(
            browser: browserFixture.browser,
            pages: browserFixture.pages,
            spaceAccess: browserFixture.spaceAccess,
            mode: mode,
            compactChromeNamespace: compactChromeNamespace,
            tabPromotionNamespace: tabPromotionNamespace,
            address: address,
            isAddressEditing: isAddressEditing,
            utilitySearchText: utilitySearchText,
            utilityFilter: utilityFilter,
            utilityPresentation: utilityPresentation,
            utilityActions: BrowserUtilityListActions(),
            spaceActionsConfiguration: MobileSpaceActionsConfiguration(
                showSettings: {},
                showArchive: {},
                showDownloads: {},
                commonListsAreExpanded: false,
                toggleCommonLists: {},
                recordCommonListsTriggerFrame: { _ in },
                togglePrivateBrowsing: {}
            ),
            activateAddress: {},
            selectTab: { _ in },
            submitAddress: {},
            openNewTab: {},
            showsCompactAddressBar: true,
            showsBottomSpaceSwitcher: true,
            compactPageIsFullyPresented: true,
            compactTransitionEnded: { _ in },
            closePrivateBrowsing: {},
            hideSidebar: {},
            selectSpace: { _ in },
            settleSpaceSelection: { _ in },
            showHistory: {},
            showPasswords: {},
            showSettings: {},
            confirmClearHistory: {}
        )
    }
}
