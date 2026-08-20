import SwiftUI

struct BrowserSidebarLoadedContent: View {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    @Binding var address: String
    @Binding var isAddressEditing: Bool
    let addressFocusRequest: Int
    let activateAddress: () -> Void
    let submitAddress: () -> Void
    let openNewTab: () -> Void
    let sidebarToggleAction: BrowserSidebarToggleAction
    let toggleSidebar: () -> Void
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID
    let utilityPresentation: BrowserUtilityPresentationState
    @Binding var utilitySearchText: String
    @Binding var utilityFilter: BrowserUtilityListFilter
    let utilityActions: BrowserUtilityListActions
    let actions: BrowserSidebarInteractionActions

    var body: some View {
        VStack(spacing: 0) {
            BrowserSpacePager(
                spaces: BrowserSidebarAccessPolicy.availableSpaces(in: browser),
                selectedSpaceID: browser.session.selectedSpaceID,
                isInteractionLocked: browser.tabDragState.item != nil
                    || browser.folderDragState.item != nil,
                selectSpace: actions.selectSpace,
                settledSpace: actions.settleSpaceSelection
            ) { space, isSelected in
                BrowserSidebarSpacePage(
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
                    commandSurfaceNamespace: commandSurfaceNamespace,
                    tabPromotionNamespace: tabPromotionNamespace,
                    utilityPresentation: utilityPresentation,
                    utilitySearchText: $utilitySearchText,
                    utilityFilter: $utilityFilter,
                    utilityActions: utilityActions,
                    actions: actions
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            BrowserSpaceSwitcher(
                browser: browser,
                downloadCenter: pages.downloadCenter,
                capabilities: capabilities,
                selectSpace: actions.selectSpace,
                accessories: switcherAccessories
            )
            .environment(
                \.colorScheme,
                browser.selectedSpace.map {
                    BrowserSpaceForegroundPolicy.colorScheme(for: $0.branding)
                } ?? .dark
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(browser.selectedSpace?.name ?? "Browser") Space")
    }

    private var switcherAccessories: BrowserSpaceSwitcherAccessories {
        BrowserSpaceSwitcherAccessories(
            sidebarToggle: BrowserSpaceSwitcherSidebarToggle(
                action: sidebarToggleAction,
                toggle: toggleSidebar
            ),
            commonLists: BrowserSpaceSwitcherCommonLists(
                isExpanded: utilityPresentation.isSwitcherExpanded,
                toggle: {
                    utilityPresentation.toggleSwitcher(
                        hasNewDownloads: !newUtilityDownloads.isEmpty
                    )
                },
                recordTriggerFrame: utilityPresentation.recordTriggerFrame
            )
        )
    }

    private var capabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities()
    }

    private var newUtilityDownloads: [BrowserDownloadItem] {
        guard let profileID = browser.selectedSpace?.profile.id else { return [] }
        return pages.downloadCenter.unacknowledgedItems(for: profileID)
    }
}
