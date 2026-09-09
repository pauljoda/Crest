import SwiftUI

/// The window's address and navigation stay in place while Space contents move
/// underneath. Their native field and popover identities belong to this leaf.
struct SidebarChrome: View {
    let context: BrowserSidebarContext
    let pages: BrowserPagePool
    let address: Binding<String>
    let isAddressEditing: Binding<Bool>
    let addressFocusRequest: Int
    let activateAddress: () -> Void
    let submitAddress: () -> Void
    let commandSurfaceNamespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let space = selectedSpace {
            let isLocked = context.spaceAccess.isLocked(space)

            VStack(spacing: 0) {
                BrowserSidebarNavigationControls(
                    port: BrowserSidebarNavigationPort(pages: pages, browser: context.browser),
                    capabilities: context.capabilities
                )
                .contentTransition(.opacity)
                .animation(
                    BrowserVisualAccessibilityPolicy.animation(
                        SpacePagerSettlement.standardAnimation, reduceMotion: reduceMotion),
                    value: [pages.canGoBack, pages.canGoForward, pages.activePage?.isLoading == true]
                )

                if context.utilityPresentation.surface == nil {
                    SpaceSidebarAddressBand(
                        space: space,
                        pages: pages,
                        capabilities: context.capabilities,
                        address: address,
                        isAddressEditing: isAddressEditing,
                        addressFocusRequest: addressFocusRequest,
                        activateAddress: activateAddress,
                        submitAddress: submitAddress,
                        commandSurfaceNamespace: commandSurfaceNamespace,
                        showExtensions: { context.chromeActions.presentExtensions?(space) },
                        siteControlPresentationChanged: {
                            context.utilityPresentation.setSiteControlPresented($0)
                        },
                        siteControlContextMenuPresentationChanged: {
                            context.utilityPresentation.setSiteControlContextMenuPresented($0)
                        }
                    )
                }
            }
            .environment(\.colorScheme, BrowserSpaceForegroundPolicy.colorScheme(for: space.branding))
            .modifier(SpaceForegroundBlend(spaces: context.availableSpaces, selectedSpaceID: space.id))
            .blur(radius: isLocked ? BrowserSidebarMetrics.lockedSpaceBlurRadius : 0)
            .redacted(reason: isLocked ? .placeholder : [])
            .allowsHitTesting(!isLocked)
            .accessibilityHidden(isLocked)
        }
    }

    private var selectedSpace: BrowserSpace? {
        context.availableSpaces.first { $0.id == context.browser.session.selectedSpaceID }
    }
}
