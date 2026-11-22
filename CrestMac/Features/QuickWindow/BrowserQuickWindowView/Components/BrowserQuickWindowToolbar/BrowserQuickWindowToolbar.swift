import SwiftUI

/// A Quick Window's page bar: the shared bar after the window's buttons, with
/// the Quick Window's own field, which edits in place where no palette
/// opens, and the Space it can move its page to at the end.
struct BrowserQuickWindowToolbar: View {
    // MARK: - Variables

    let model: BrowserQuickWindowModel
    @Binding var addressText: String
    @Binding var isAddressEditing: Bool
    let addressFocusRequest: Int
    let commandSurfaceNamespace: Namespace.ID
    let commandPaletteHandoff: BrowserCommandPaletteHandoff
    let promote: (BrowserSpaceRuntimeAssignment) -> Void

    @Environment(\.browserMacWindows) private var windows

    var body: some View {
        BrowserPageBar(
            metrics: .quickWindow,
            windowControlsClearance: BrowserQuickWindowLayout.windowControlClearance,
            port: port,
            branding: model.spaceModel?.settings.look
        ) {
            BrowserQuickWindowAddressControl(
                model: model,
                addressText: $addressText,
                isAddressEditing: $isAddressEditing,
                addressFocusRequest: addressFocusRequest,
                commandSurfaceNamespace: commandSurfaceNamespace,
                commandPaletteHandoff: commandPaletteHandoff
            )
        } extensions: {
            if let space = model.spaceModel {
                BrowserEngineToolbarAccessory(page: model.page, space: space, browser: model.browser)
            }
        } trailingAccessory: {
            // Names the Space while there is room, and is cut short before
            // the address field gives up its minimum.
            BrowserPeekDestinationControl(
                spaces: model.availableSpaceModels.map(\.identity),
                selectedSpaceID: model.selectedAssignment.spaceID,
                style: .toolbar,
                openInSpace: promote
            )
        }
    }

    private var port: BrowserSidebarNavigationPort {
        BrowserSidebarNavigationPort(
            page: { [model] in model.page },
            recordActivity: { [model] in model.recordUserActivity() },
            showHistory: showHistory
        )
    }

    // MARK: - Actions - History

    /// A Quick Window keeps no History of its own: the browser window's opens.
    private func showHistory() {
        windows?.contextBringingBrowserWindowForward()?.chrome.presentUtility(.history)
    }
}
