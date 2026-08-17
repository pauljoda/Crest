import SwiftUI

struct BrowserRootSidebarContent: View {
    let model: BrowserRootModel
    let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BrowserSidebar(
            browser: model.browser,
            pages: model.pages,
            spaceAccess: model.spaceAccess,
            address: model.addressBinding,
            isAddressEditing: model.isAddressEditingBinding,
            addressFocusRequest: model.chrome.addressFocusRequest,
            activateAddress: { model.chrome.openLocation(model.address) },
            submitAddress: model.submitAddress,
            openNewTab: model.chrome.presentCommandPalette,
            sidebarToggleAction: model.sidebarPresentation.sidebarToggleAction,
            toggleSidebar: {
                model.toggleSidebar(reduceMotion: reduceMotion)
            },
            commandSurfaceNamespace: commandSurfaceNamespace,
            tabPromotionNamespace: tabPromotionNamespace,
            utilityPresentation: model.chrome.utilityPresentation,
            spaceSettingsPresentation: spaceSettingsPresentation
        )
    }
}
