import SwiftUI

struct MobileBrowserSidebarSurface: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let dataDeleter: any BrowserSpaceDataDeleting
    let spaceAccess: BrowserSpaceAccessController
    let mode: MobileBrowserSidebarMode
    let compactChromeNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID
    @Binding var address: String
    @Binding var isAddressEditing: Bool
    let activateAddress: () -> Void
    let selectTab: (TabID) -> Void
    let submitAddress: () -> Void
    let openURL: (URL) -> Void
    let openNewTab: () -> Void
    let showsCompactAddressBar: Bool
    let showsBottomSpaceSwitcher: Bool
    let compactPageIsFullyPresented: Bool
    let compactTransitionEnded: (CGSize) -> Void
    let togglePrivateBrowsing: () -> Void
    let closePrivateBrowsing: () -> Void
    let hideSidebar: () -> Void
    let utilityPresentation: BrowserUtilityPresentationState

    var body: some View {
        MobileBrowserSidebar(
            browser: browser,
            pages: pages,
            dataDeleter: dataDeleter,
            spaceAccess: spaceAccess,
            mode: mode,
            compactChromeNamespace: compactChromeNamespace,
            tabPromotionNamespace: tabPromotionNamespace,
            address: $address,
            isAddressEditing: $isAddressEditing,
            activateAddress: activateAddress,
            selectTab: selectTab,
            submitAddress: submitAddress,
            openURL: openURL,
            openNewTab: openNewTab,
            showsCompactAddressBar: showsCompactAddressBar,
            showsBottomSpaceSwitcher: showsBottomSpaceSwitcher,
            compactPageIsFullyPresented: compactPageIsFullyPresented,
            compactTransitionEnded: compactTransitionEnded,
            togglePrivateBrowsing: togglePrivateBrowsing,
            closePrivateBrowsing: closePrivateBrowsing,
            hideSidebar: hideSidebar,
            utilityPresentation: utilityPresentation
        )
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}
