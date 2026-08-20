import SwiftUI

/// The compact shell's half of the sidebar: its layout choices, its namespaces,
/// and the closures only this shell can answer.
///
/// Everything the sidebar itself owns arrives in `context`. What is left here is
/// what the adaptive shell decides for one placement — where the utility lists
/// come up, whether the pager paints its own ground, whether the bottom inset is
/// held open — plus the page-facing bindings a single compact page needs.
struct MobileBrowserSidebarContentConfiguration {
    let context: BrowserSidebarContext
    let pages: MobileBrowserPageStore
    let compactChromeNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID
    let address: Binding<String>
    let isAddressEditing: Binding<Bool>
    let spaceActionsConfiguration: MobileSpaceActionsConfiguration
    let utilityPresentationStyle: MobileBrowserSidebarUtilityPresentationStyle
    let showsPageBackdrop: Bool
    let reservesBottomChromeInset: Bool
    let sidebarToggleUndocks: Bool
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
}
