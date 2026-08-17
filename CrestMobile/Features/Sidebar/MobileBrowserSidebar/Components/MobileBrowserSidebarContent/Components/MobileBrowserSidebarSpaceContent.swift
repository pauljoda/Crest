import SwiftUI

struct MobileBrowserSidebarSpaceContent: View {
    let configuration: MobileBrowserSidebarContentConfiguration
    let space: BrowserSpace
    let isSelected: Bool

    var body: some View {
        if configuration.mode == .regularSidebar,
            let utilitySurface = configuration.utilityPresentation.surface
        {
            if isSelected {
                BrowserUtilityListContent(
                    surface: utilitySurface,
                    space: space,
                    downloads: configuration.pages.downloadCenter.items(
                        for: space.profile.id
                    ),
                    searchText: configuration.utilitySearchText.wrappedValue,
                    filter: configuration.utilityFilter.wrappedValue,
                    actions: configuration.utilityActions,
                    dismissOnBlankSpace: {
                        configuration.utilityPresentation.handleInteraction(
                            .sidebarBlankSpace
                        )
                    }
                )
            } else {
                Color.clear
            }
        } else {
            MobileBrowserSpacePage(
                space: space,
                browser: configuration.browser,
                pages: configuration.pages,
                spaceAccess: configuration.spaceAccess,
                mode: configuration.mode,
                tabPromotionNamespace: configuration.tabPromotionNamespace,
                selectTab: configuration.selectTab,
                openNewTab: configuration.openNewTab,
                showHistory: configuration.showHistory,
                showPasswords: configuration.showPasswords,
                showSettings: configuration.showSettings,
                closePrivateBrowsing: configuration.closePrivateBrowsing,
                compactPageIsFullyPresented:
                    configuration.compactPageIsFullyPresented
            )
        }
    }
}
