import SwiftUI

struct BrowserSidebarSpacePage: View {
    let space: BrowserSpace
    let isSelected: Bool
    let context: BrowserSidebarContext
    let pages: BrowserPagePool
    @Binding var address: String
    @Binding var isAddressEditing: Bool
    let addressFocusRequest: Int
    let activateAddress: () -> Void
    let submitAddress: () -> Void
    let openNewTab: () -> Void
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID

    private var isLocked: Bool {
        context.spaceAccess.isLocked(space)
    }

    var body: some View {
        SpaceSidebarContent(
            space: space,
            isSelected: isSelected,
            browser: context.browser,
            pages: pages,
            spaceAccess: context.spaceAccess,
            capabilities: context.capabilities,
            address: $address,
            isAddressEditing: $isAddressEditing,
            addressFocusRequest: addressFocusRequest,
            activateAddress: activateAddress,
            submitAddress: submitAddress,
            openNewTab: openNewTab,
            showHistory: context.chromeActions.presentHistory,
            showExtensions: showExtensions,
            siteControlPresentationChanged: {
                context.utilityPresentation.setSiteControlPresented($0)
            },
            siteControlContextMenuPresentationChanged: {
                context.utilityPresentation.setSiteControlContextMenuPresented($0)
            },
            commandSurfaceNamespace: commandSurfaceNamespace,
            tabPromotionNamespace: tabPromotionNamespace,
            editSpace: { context.chromeActions.presentSpaceSettings(space) },
            createSpace: createSpace,
            utilitySurface: context.utilityPresentation.surface,
            utilitySearchText: context.utilitySearchText,
            utilityFilter: context.utilityFilter,
            utilityDownloads: context.pageAccess.downloadCenter.items(
                for: space.profile.id
            ),
            utilityActions: context.utilityActions,
            dismissUtilityOnBlankSpace: context.dismissUtilityOnBlankSpace,
            clearHistory: { context.confirmClearHistory(space) }
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

    private func showExtensions() {
        context.chromeActions.presentExtensions?(space)
    }

    private func createSpace() {
        context.chromeActions.createSpace?()
    }
}
