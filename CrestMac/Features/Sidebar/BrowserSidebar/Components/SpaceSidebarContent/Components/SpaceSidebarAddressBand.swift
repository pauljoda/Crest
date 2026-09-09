import SwiftUI

/// The windowed sidebar's address band: the field, the two site controls that
/// flank it, and the pinned extension strip that sits directly under it.
///
/// The strip is part of the band rather than a sibling of it because the two
/// share one seam — the field gives up its bottom inset when the strip has
/// anything to show.
struct SpaceSidebarAddressBand: View {
    let space: BrowserSpace
    let pages: BrowserPagePool
    let capabilities: BrowserInteractionCapabilities
    let address: Binding<String>
    let isAddressEditing: Binding<Bool>
    let addressFocusRequest: Int
    let activateAddress: () -> Void
    let submitAddress: () -> Void
    let commandSurfaceNamespace: Namespace.ID
    let showExtensions: () -> Void
    let siteControlPresentationChanged: (Bool) -> Void
    let siteControlContextMenuPresentationChanged: (Bool) -> Void
    let hasPinnedExtensionActions: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BrowserSidebarAddressField(configuration: addressConfiguration) {
            if let siteControl {
                BrowserAddressSecurityButton(
                    page: siteControl.page,
                    isSecure: isSecure
                )
            }
        } trailingAccessory: {
            if let siteControl {
                BrowserSiteControlButton(configuration: siteControl)
            }
        }
        .contentTransition(.opacity)
        .animation(
            BrowserVisualAccessibilityPolicy.animation(
                SpacePagerSettlement.standardAnimation, reduceMotion: reduceMotion),
            value: isAddressEditing.wrappedValue ? nil : address.wrappedValue
        )
        .padding(.horizontal, BrowserChromeLayout.sidebarHorizontalInset)
        .padding(
            .bottom,
            BrowserPinnedExtensionStripLayoutPolicy.addressBottomInset(
                hasPinnedExtensions: hasPinnedExtensionActions
            )
        )

        BrowserPinnedExtensionStrip(
            spaceID: space.id,
            selectedTabID: space.selectedTabID,
            extensionControllerPool: pages.extensionControllerPool
        )
    }

    private var addressConfiguration: BrowserSidebarAddressFieldConfiguration {
        BrowserSidebarAddressFieldConfiguration(
            text: address,
            isEditing: isAddressEditing,
            focusRequest: addressFocusRequest,
            isSecure: isSecure,
            progress: displayedPage?.estimatedProgress ?? 0,
            isLoading: displayedPage?.isLoading == true,
            hasResidentPage: displayedPage != nil,
            hasActiveSite: siteControl != nil,
            capabilities: capabilities,
            activate: activateAddress,
            submit: submitAddress,
            morphNamespace: commandSurfaceNamespace,
            morphID: "crest-address-command-\(space.id)"
        )
    }

    private var selectedTab: BrowserTab? {
        guard let selectedTabID = space.selectedTabID else { return nil }
        return space.tabs.first { $0.id == selectedTabID }
    }

    private var displayedPage: BrowserPage? {
        guard let selectedTabID = space.selectedTabID else { return nil }
        let assignment = BrowserTabRuntimeAssignment(
            tabID: selectedTabID, spaceID: space.id, profileID: space.profile.id
        )
        return pages.activePage(matching: assignment)
    }

    private var isSecure: Bool {
        if let page = displayedPage { return page.hasOnlySecureContent }
        return selectedTab?.url?.scheme?.lowercased() == "https"
    }

    private var siteControl: BrowserSiteControlConfiguration? {
        guard let page = displayedPage,
            page.displayURL != nil
        else {
            return nil
        }
        return BrowserSiteControlConfiguration(
            page: page,
            space: space,
            selectedTabID: space.selectedTabID,
            extensionControllerPool: pages.extensionControllerPool,
            permissionCenter: pages.permissionCenter,
            manageExtensions: showExtensions,
            presentationChanged: siteControlPresentationChanged,
            contextMenuPresentationChanged:
                siteControlContextMenuPresentationChanged
        )
    }
}
