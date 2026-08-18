import SwiftUI

struct BrowserSidebarSpacePage: View {
    let space: BrowserSpace
    let isSelected: Bool
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    @Binding var address: String
    @Binding var isAddressEditing: Bool
    let addressFocusRequest: Int
    let activateAddress: () -> Void
    let submitAddress: () -> Void
    let openNewTab: () -> Void
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID
    let utilityPresentation: BrowserUtilityPresentationState
    @Binding var utilitySearchText: String
    @Binding var utilityFilter: BrowserUtilityListFilter
    let utilityActions: BrowserUtilityListActions
    let actions: BrowserSidebarInteractionActions

    private var isLocked: Bool {
        spaceAccess.isLocked(space)
    }

    var body: some View {
        SpaceSidebarContent(
            space: space,
            isSelected: isSelected,
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            address: $address,
            isAddressEditing: $isAddressEditing,
            addressFocusRequest: addressFocusRequest,
            activateAddress: activateAddress,
            submitAddress: submitAddress,
            openNewTab: openNewTab,
            showHistory: { utilityPresentation.present(.history) },
            showExtensions: { actions.presentExtensions(space) },
            siteControlPresentationChanged: {
                utilityPresentation.setSiteControlPresented($0)
            },
            siteControlContextMenuPresentationChanged: {
                utilityPresentation.setSiteControlContextMenuPresented($0)
            },
            commandSurfaceNamespace: commandSurfaceNamespace,
            tabPromotionNamespace: tabPromotionNamespace,
            editSpace: { actions.presentSpaceSettings(space) },
            createSpace: actions.createSpace,
            utilitySurface: utilityPresentation.surface,
            utilitySearchText: $utilitySearchText,
            utilityFilter: $utilityFilter,
            utilityDownloads: pages.downloadCenter.items(for: space.profile.id),
            utilityActions: utilityActions,
            dismissUtilityOnBlankSpace: actions.dismissUtilityOnBlankSpace,
            clearHistory: { actions.confirmClearHistory(space) }
        )
        .environment(
            \.colorScheme,
            BrowserSpaceForegroundPolicy.colorScheme(for: space.branding)
        )
        .blur(
            radius: isLocked
                ? BrowserSidebarMetrics.lockedSpaceBlurRadius
                : 0
        )
        .redacted(reason: isLocked ? .placeholder : [])
        .allowsHitTesting(isSelected && !isLocked)
        .accessibilityHidden(!isSelected || isLocked)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(space.name) Space")
    }
}
