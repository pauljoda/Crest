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
                    sidebarToggleAction: sidebarToggleAction,
                    toggleSidebar: toggleSidebar,
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

            SpaceSwitcher(
                browser: browser,
                pages: pages,
                spaceAccess: spaceAccess,
                selectSpace: actions.selectSpace,
                commonListsAreExpanded: utilityPresentation.isSwitcherExpanded,
                toggleCommonLists: utilityPresentation.toggleSwitcher,
                recordCommonListsTriggerFrame:
                    utilityPresentation.recordTriggerFrame
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
}

#Preview("Browser Sidebar Loaded Content") {
    @Previewable @State var address = "https://developer.apple.com"
    @Previewable @State var isAddressEditing = false
    @Previewable @State var utilitySearchText = ""
    @Previewable @State var utilityFilter = BrowserUtilityListFilter.all
    @Previewable @Namespace var commandSurfaceNamespace
    @Previewable @Namespace var tabPromotionNamespace
    let browser = BrowserSidebarPreviewFixture.makeBrowser()
    let pages = BrowserSidebarPreviewFixture.makePages()
    let spaceAccess = BrowserSidebarPreviewFixture.makeSpaceAccess()
    BrowserSidebarLoadedContent(
        browser: browser,
        pages: pages,
        spaceAccess: spaceAccess,
        address: $address,
        isAddressEditing: $isAddressEditing,
        addressFocusRequest: 0,
        activateAddress: {},
        submitAddress: {},
        openNewTab: {},
        sidebarToggleAction: .hide,
        toggleSidebar: {},
        commandSurfaceNamespace: commandSurfaceNamespace,
        tabPromotionNamespace: tabPromotionNamespace,
        utilityPresentation:
            BrowserSidebarPreviewFixture.makeUtilityPresentation(),
        utilitySearchText: $utilitySearchText,
        utilityFilter: $utilityFilter,
        utilityActions: BrowserSidebarPreviewFixture.makeUtilityActions(
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess
        ),
        actions: BrowserSidebarPreviewFixture.makeInteractionActions()
    )
    .frame(width: BrowserChromeLayout.sidebarIdealWidth, height: 680)
}
