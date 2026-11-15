import SwiftUI

/// The window's address bar along the top of a lone page while the address
/// bar is on top: the sidebar's own navigation strip and address field, moved
/// here rather than repeated, with equal room above and below them.
///
/// The sidebar draws the same two controls under the same identities
/// (``BrowserWindowChromeMorph``) while the address bar is in the sidebar, so
/// changing placement carries them from one place to the other. A split's
/// cards carry bars of their own instead, so the window hides this one while
/// its page shows a split. The bar's empty parts move the window, as the
/// sidebar's strip does.
struct BrowserWindowAddressBar: View {
    // MARK: - Static Variables

    /// Where the window's own buttons end, from its leading edge: the zoom
    /// button ends 80 pt in, and the bar keeps 12 pt clear of it.
    private static let windowControlsTrailingEdge: CGFloat = 92
    /// How far the bar's controls stand in from the card's edges.
    private static let horizontalPadding: CGFloat = 8
    private static let sidebarToggleSize = CGSize(width: 30, height: 30)

    // MARK: - Variables

    let model: BrowserRootModel
    let space: SpaceModel
    let commandSurfaceNamespace: Namespace.ID

    @Environment(\.browserWindowCornerRadius) private var windowCornerRadius
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isLocked = model.spaceAccess.isLocked(space)
        HStack(spacing: BrowserPageBarMetrics.pageCard.spacing) {
            if showsSidebarToggle {
                sidebarToggle
            }
            BrowserSidebarNavigationControls(
                port: BrowserSidebarNavigationPort(
                    pages: model.pages, browser: model.browser,
                    showHistory: { model.chrome.presentUtility(.history) }),
                capabilities: BrowserInteractionCapabilities(),
                besideWindowControls: false
            )
            .fixedSize()
            .matchedGeometryEffect(
                id: BrowserWindowChromeMorph.navigation, in: commandSurfaceNamespace, properties: .frame)
            BrowserPageBarFieldLayout(
                fieldMinimumWidth: BrowserPageBarMetrics.pageCard.fieldMinimumWidth,
                widthBeforeExtensions: BrowserPageBarMetrics.pageCard.widthBeforeExtensions,
                spacing: BrowserPageBarMetrics.pageCard.spacing
            ) {
                addressField
                BrowserEngineToolbarAccessory(page: model.pages.activePage, space: space, browser: model.browser)
            }
            .layoutPriority(1)
        }
        .padding(.leading, insets.leading + Self.horizontalPadding + windowControlsClearance)
        .padding(.trailing, insets.trailing + Self.horizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: BrowserPageBarMetrics.topSectionHeight)
        .modifier(SpaceColorScheme(branding: space.settings.look))
        .modifier(SpaceForegroundBlend(spaces: model.browser.availableSpaces, selectedSpaceID: space.id))
        .blur(radius: isLocked ? BrowserSidebarMetrics.lockedSpaceBlurRadius : 0)
        .redacted(reason: isLocked ? .placeholder : [])
        .allowsHitTesting(!isLocked)
        .accessibilityHidden(isLocked)
        .background {
            // Only the bar's empty parts act as the title bar. Its controls
            // keep their own presses.
            BrowserWindowTitleBarSurface()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Address bar")
        .accessibilityIdentifier("window-address-bar")
    }

    /// The sidebar's own address field, reporting where it lies so the
    /// window's palette can drop out of it here.
    private var addressField: some View {
        SpaceSidebarAddressBand(
            space: space,
            offersSiteControls: !model.browser.isDeleting(space.id),
            selectedTabID: model.browser.selectedTabID(in: space.id),
            pages: model.pages,
            capabilities: BrowserInteractionCapabilities(),
            address: model.addressBinding,
            isAddressEditing: model.isAddressEditingBinding,
            addressFocusRequest: model.chrome.addressFocusRequest,
            activateAddress: { model.chrome.openLocation(model.address) },
            submitAddress: model.submitAddress,
            commandSurfaceNamespace: commandSurfaceNamespace,
            commandPaletteHandoff: model.commandPaletteHandoff(reduceMotion: reduceMotion),
            siteControlPresentationChanged: {
                model.chrome.utilityPresentation.setSiteControlPresented($0)
            },
            siteControlContextMenuPresentationChanged: {
                model.chrome.utilityPresentation.setSiteControlContextMenuPresented($0)
            },
            horizontalInset: 0
        )
        .modifier(SurfaceToneAppearance())
        .matchedGeometryEffect(
            id: BrowserWindowChromeMorph.addressField, in: commandSurfaceNamespace, properties: .frame
        )
        .background { BrowserWindowTitleBarControlArea() }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            model.pageBarFieldFrames.registerWindowFrame(frame)
        }
        .onDisappear { model.pageBarFieldFrames.registerWindowFrame(nil) }
    }

    private var sidebarToggle: some View {
        let action = model.sidebarPresentation.sidebarToggleAction
        return Button(
            action.title,
            systemImage: BrowserDeviceAppearanceStore.shared.sidebarOnRight ? "sidebar.right" : "sidebar.left"
        ) {
            model.toggleSidebar(reduceMotion: reduceMotion)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(CrestChromeButtonStyle(controlSize: Self.sidebarToggleSize))
        .help(action.title)
        .accessibilityIdentifier("window-address-bar-sidebar-toggle")
    }

    /// The window's frame around its page, which the card stands inside.
    private var insets: EdgeInsets {
        BrowserChromeAppearance.device(windowCornerRadius: nil).pageInsets(
            docked: model.sidebarPresentation.reservesSidebarWidth, direction: layoutDirection)
    }

    /// The sidebar's toggle shows here while the sidebar is not docked, so a
    /// hidden sidebar is a click away.
    private var showsSidebarToggle: Bool {
        !model.sidebarPresentation.reservesSidebarWidth
    }

    /// The room the bar leaves at its leading edge for the window's buttons
    /// where they stand over it. They stand there unless a sidebar docked on
    /// that edge holds them, and then the page, and the bar with it, starts
    /// at the window's own leading edge. A full-screen window has no corners
    /// and shows no buttons.
    private var windowControlsClearance: CGFloat {
        guard model.windowControlsStandOverPage(in: layoutDirection), windowCornerRadius != nil else { return 0 }
        return max(0, Self.windowControlsTrailingEdge - insets.leading - Self.horizontalPadding)
    }
}
