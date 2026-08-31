import SwiftUI

/// The windowed shell's sidebar adapter: it resolves what this shell can do,
/// binds the sidebar's ports to the window's card pool, and answers the chrome's
/// presentation with the settings scene.
///
/// The `openWindow` action only exists where the Environment is read, so the
/// scene-pointing implementations live here rather than travelling down as data.
struct BrowserRootSidebarContent: View {
    let model: BrowserRootModel
    let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        BrowserSidebar(
            browser: model.browser,
            pageAccess: pageAccess,
            spaceAccess: model.spaceAccess,
            capabilities: capabilities,
            utilityCoordinator: utilityCoordinator,
            utilityPresentation: model.chrome.utilityPresentation,
            chromeActions: chromeActions
        ) { context in
            BrowserSidebarLoadedContent(
                context: context,
                pages: model.pages,
                address: model.addressBinding,
                isAddressEditing: model.isAddressEditingBinding,
                addressFocusRequest: model.chrome.addressFocusRequest,
                activateAddress: { model.chrome.openLocation(model.address) },
                submitAddress: model.submitAddress,
                openNewTab: model.openNewTab,
                sidebarToggleAction:
                    model.sidebarPresentation.sidebarToggleAction,
                toggleSidebar: {
                    model.toggleSidebar(reduceMotion: reduceMotion)
                },
                commandSurfaceNamespace: commandSurfaceNamespace,
                tabPromotionNamespace: tabPromotionNamespace
            )
        }
    }

    /// What this shell can do: a pointer rests over the chrome, nothing is aimed
    /// at with a finger, and the window never zooms a page in.
    private var capabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities()
    }

    private var pageAccess: BrowserSidebarPageAccess {
        BrowserSidebarPageAccess(pages: model.pages, browser: model.browser)
    }

    private var utilityCoordinator: BrowserSidebarUtilityCoordinator {
        BrowserSidebarUtilityCoordinator(
            browser: model.browser,
            pages: model.pages,
            spaceAccess: model.spaceAccess
        )
    }

    private var chromeActions: BrowserSidebarChromeActions {
        BrowserSidebarChromeActions(
            presentSpaceSettings: presentSpaceSettings(for:),
            presentHistory: { model.chrome.utilityPresentation.present(.history) },
            presentExtensions: presentExtensions(for:),
            createSpace: createSpace
        )
    }

    private func presentSpaceSettings(for space: BrowserSpace) {
        spaceSettingsPresentation.present(
            assignment: BrowserSpaceRuntimeAssignment(space: space)
        )
        openWindow(id: BrowserSceneID.settings.rawValue)
    }

    private func presentExtensions(for space: BrowserSpace) {
        spaceSettingsPresentation.present(
            .extensions,
            assignment: BrowserSpaceRuntimeAssignment(space: space)
        )
        openWindow(id: BrowserSceneID.settings.rawValue)
    }

    private func createSpace() {
        model.browser.addSpace()
        guard let space = model.browser.selectedSpace else { return }
        model.pages.select(session: model.browser.session)
        presentSpaceSettings(for: space)
    }
}
