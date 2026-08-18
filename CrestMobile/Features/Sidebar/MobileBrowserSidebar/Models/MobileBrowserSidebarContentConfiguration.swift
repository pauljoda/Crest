import SwiftUI

struct MobileBrowserSidebarContentConfiguration {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let mode: MobileBrowserSidebarMode
    let compactChromeNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID
    let address: Binding<String>
    let isAddressEditing: Binding<Bool>
    let utilitySearchText: Binding<String>
    let utilityFilter: Binding<BrowserUtilityListFilter>
    let utilityPresentation: BrowserUtilityPresentationState
    let utilityActions: BrowserUtilityListActions
    let spaceActionsConfiguration: MobileSpaceActionsConfiguration
    let activateAddress: () -> Void
    let selectTab: (TabID) -> Void
    let submitAddress: () -> Void
    let openNewTab: () -> Void
    let showsCompactAddressBar: Bool
    let showsBottomSpaceSwitcher: Bool
    let compactPageIsFullyPresented: Bool
    let compactTransitionEnded: (CGSize) -> Void
    let closePrivateBrowsing: () -> Void
    let toggleSidebar: () -> Void
    let showsSidebarToggle: Bool
    let sidebarIsDocked: Bool
    let selectSpace: (SpaceID) -> Void
    let settleSpaceSelection: (SpaceID) -> Void
    let showHistory: () -> Void
    let showPasswords: () -> Void
    let showSettings: () -> Void
    let confirmClearHistory: () -> Void
}
