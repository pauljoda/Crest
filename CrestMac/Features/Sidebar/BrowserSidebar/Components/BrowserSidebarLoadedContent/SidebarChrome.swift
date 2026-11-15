import SwiftUI

/// The window's address and navigation stay in place while Space contents move
/// underneath. Their native field and popover identities belong to this leaf.
///
/// With the address bar on top the same strip and field stand along the top
/// of the page instead (``BrowserWindowAddressBar``), under the same
/// identities, so changing placement carries them across; this leaf keeps
/// only the empty strip under the window's buttons.
struct SidebarChrome: View {
    let context: BrowserSidebarContext
    let pages: BrowserPagePool
    let address: Binding<String>
    let isAddressEditing: Binding<Bool>
    let addressFocusRequest: Int
    let activateAddress: () -> Void
    let submitAddress: () -> Void
    let commandSurfaceNamespace: Namespace.ID
    let commandPaletteHandoff: BrowserCommandPaletteHandoff
    /// Whether the sidebar is docked, where its strip lies under the window's
    /// buttons, rather than floating below the page cards' bars.
    var isDocked = true

    var body: some View {
        if let space = selectedSpace {
            let isLocked = context.spaceAccess.isLocked(space)

            VStack(spacing: 0) {
                if BrowserDeviceAppearanceStore.shared.addressBarPlacement.showsBarInPageCards {
                    // The address bar stands along the top of the page, so the
                    // strip under the window's buttons is empty chrome that
                    // moves the window. A floating card hangs below the top
                    // section and needs only a margin.
                    Color.clear
                        .frame(height: isDocked ? BrowserChromeLayout.sidebarTitlebarHeight : CrestSpacing.small)
                        .background { BrowserWindowTitleBarSurface() }
                } else {
                    VStack(spacing: 0) {
                        navigationAndAddress(space)
                    }
                    .transition(BrowserWindowChromeMorph.transition)
                }
            }
            .modifier(SpaceColorScheme(branding: space.settings.look))
            .modifier(SpaceForegroundBlend(spaces: context.availableSpaces, selectedSpaceID: space.id))
            .blur(radius: isLocked ? BrowserSidebarMetrics.lockedSpaceBlurRadius : 0)
            .redacted(reason: isLocked ? .placeholder : [])
            .allowsHitTesting(!isLocked)
            .accessibilityHidden(isLocked)
        }
    }

    /// The navigation strip beside the window's buttons, and the address field
    /// under it while no list takes its place.
    @ViewBuilder
    private func navigationAndAddress(_ space: SpaceModel) -> some View {
        BrowserSidebarNavigationControls(
            port: BrowserSidebarNavigationPort(
                pages: pages, browser: context.browser, showHistory: context.chromeActions.presentHistory),
            capabilities: context.capabilities
        )
        .matchedGeometryEffect(id: BrowserWindowChromeMorph.navigation, in: commandSurfaceNamespace, properties: .frame)
        .background {
            // Only the empty navigation-strip background acts as the
            // title bar. Controls and tab gestures keep their input.
            BrowserWindowTitleBarSurface()
        }

        if context.utilityPresentation.surface == nil {
            SpaceSidebarAddressBand(
                space: space,
                // A split's cards carry Site Controls in their own bars, where
                // each card's prompts stay whichever card has focus.
                offersSiteControls: !context.browser.isDeleting(space.id) && context.browser.cards(in: space).count < 2,
                selectedTabID: context.browser.selectedTabID(in: space.id),
                pages: pages,
                capabilities: context.capabilities,
                address: address,
                isAddressEditing: isAddressEditing,
                addressFocusRequest: addressFocusRequest,
                activateAddress: activateAddress,
                submitAddress: submitAddress,
                commandSurfaceNamespace: commandSurfaceNamespace,
                commandPaletteHandoff: commandPaletteHandoff,
                siteControlPresentationChanged: {
                    context.utilityPresentation.setSiteControlPresented($0)
                },
                siteControlContextMenuPresentationChanged: {
                    context.utilityPresentation.setSiteControlContextMenuPresented($0)
                }
            )
            .modifier(SurfaceToneAppearance())
            .matchedGeometryEffect(
                id: BrowserWindowChromeMorph.addressField, in: commandSurfaceNamespace, properties: .frame)
        }
    }

    /// The Space the window shows, unless it is being deleted.
    private var selectedSpace: SpaceModel? {
        context.browser.shownSpace
    }
}
