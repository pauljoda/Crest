import SwiftUI

/// The windowed shell's sidebar layout: a clipped Space pager with the Space
/// switcher resting under it.
///
/// Everything about *what* the sidebar does comes down from `BrowserSidebar`
/// through the context. What this view owns is the arrangement, the switcher's
/// accessories, and the page body only a windowed card pool can answer for.
struct BrowserSidebarLoadedContent: View {
    let context: BrowserSidebarContext
    let pages: BrowserPagePool
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

    var body: some View {
        VStack(spacing: 0) {
            BrowserSidebarSpacePager(context: context) { space, isSelected in
                BrowserSidebarSpacePage(
                    space: space,
                    isSelected: isSelected,
                    context: context,
                    pages: pages,
                    address: $address,
                    isAddressEditing: $isAddressEditing,
                    addressFocusRequest: addressFocusRequest,
                    activateAddress: activateAddress,
                    submitAddress: submitAddress,
                    openNewTab: openNewTab,
                    commandSurfaceNamespace: commandSurfaceNamespace,
                    tabPromotionNamespace: tabPromotionNamespace
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            BrowserSpaceSwitcher(
                browser: context.browser,
                downloadCenter: context.pageAccess.downloadCenter,
                capabilities: context.capabilities,
                selectSpace: context.selectSpace,
                accessories: switcherAccessories
            )
            .environment(
                \.colorScheme,
                context.browser.selectedSpace.map {
                    BrowserSpaceForegroundPolicy.colorScheme(for: $0.branding)
                } ?? .dark
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(context.browser.selectedSpace?.name ?? "Browser") Space"
        )
    }

    private var switcherAccessories: BrowserSpaceSwitcherAccessories {
        BrowserSpaceSwitcherAccessories(
            sidebarToggle: BrowserSpaceSwitcherSidebarToggle(
                action: sidebarToggleAction,
                toggle: toggleSidebar
            ),
            commonLists: BrowserSpaceSwitcherCommonLists(
                isExpanded: context.utilityPresentation.isSwitcherExpanded,
                toggle: context.toggleUtilitySwitcher,
                recordTriggerFrame:
                    context.utilityPresentation.recordTriggerFrame
            )
        )
    }
}

#Preview("Browser Sidebar — Tabs") {
    @Previewable @State var address = "https://developer.apple.com"
    @Previewable @State var isAddressEditing = false
    @Previewable @Namespace var commandSurfaceNamespace
    @Previewable @Namespace var tabPromotionNamespace
    let browser = BrowserSidebarPreviewFixture.makeBrowser()
    let pages = BrowserSidebarPreviewFixture.makePages()
    let spaceAccess = BrowserSidebarPreviewFixture.makeSpaceAccess()
    BrowserSidebar(
        browser: browser,
        pageAccess: BrowserSidebarPageAccess(pages: pages, browser: browser),
        spaceAccess: spaceAccess,
        capabilities: BrowserInteractionCapabilities(),
        utilityCoordinator: BrowserSidebarUtilityCoordinator(
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess
        ),
        utilityPresentation:
            BrowserSidebarPreviewFixture.makeUtilityPresentation(),
        chromeActions: BrowserSidebarPreviewFixture.makeChromeActions()
    ) { context in
        BrowserSidebarLoadedContent(
            context: context,
            pages: pages,
            address: $address,
            isAddressEditing: $isAddressEditing,
            addressFocusRequest: 0,
            activateAddress: { isAddressEditing = true },
            submitAddress: {},
            openNewTab: {},
            sidebarToggleAction: .hide,
            toggleSidebar: {},
            commandSurfaceNamespace: commandSurfaceNamespace,
            tabPromotionNamespace: tabPromotionNamespace
        )
    }
    .frame(width: BrowserChromeLayout.sidebarIdealWidth, height: 680)
}
