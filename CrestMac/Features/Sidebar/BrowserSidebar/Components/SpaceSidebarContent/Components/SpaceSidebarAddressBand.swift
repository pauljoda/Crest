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
    let isSelected: Bool
    let capabilities: BrowserInteractionCapabilities
    @Binding var address: String
    @Binding var isAddressEditing: Bool
    let addressFocusRequest: Int
    let activateAddress: () -> Void
    let submitAddress: () -> Void
    let commandSurfaceNamespace: Namespace.ID
    let showExtensions: () -> Void
    let siteControlPresentationChanged: (Bool) -> Void
    let siteControlContextMenuPresentationChanged: (Bool) -> Void
    let hasPinnedExtensionActions: Bool

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
            text: displayedAddress,
            isEditing: displayedEditing,
            focusRequest: addressFocusRequest,
            isSecure: isSecure,
            progress: isSelected ? pages.activePage?.estimatedProgress ?? 0 : 0,
            isLoading: isSelected && pages.activePage?.isLoading == true,
            hasResidentPage: isSelected && pages.activePage != nil,
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

    private var displayedAddress: Binding<String> {
        isSelected
            ? $address
            : .constant(selectedTab?.url?.absoluteString ?? "")
    }

    private var displayedEditing: Binding<Bool> {
        isSelected ? $isAddressEditing : .constant(false)
    }

    private var isSecure: Bool {
        isSelected
            ? pages.activePage?.hasOnlySecureContent == true
            : selectedTab?.url?.scheme?.lowercased() == "https"
    }

    private var siteControl: BrowserSiteControlConfiguration? {
        guard isSelected,
            let page = pages.activePage,
            page.displayURL != nil,
            page.spaceID == space.id
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
