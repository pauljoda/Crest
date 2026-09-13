import SwiftUI

struct BrowserFolderOrganizationMenu: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let folder: BrowserFolder
    let assignment: BrowserFolderRuntimeAssignment
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let createNestedFolder: () -> Void
    let renameFolder: () -> Void
    let changeColor: () -> Void
    let changeIcon: () -> Void
    let deleteFolder: () -> Void

    @Environment(\.browserInteractionCapabilities) private var capabilities

    var body: some View {
        Group {
            if capabilities.allowsMultiSelection,
                let request = BrowserSidebarSelection.request(
                    for: .folder(folder.id), browser: browser, reorder: sidebarInteraction.sidebarReorderState)
            {
                BrowserTabBatchMenu(request: request, browser: browser, spaceAccess: spaceAccess)
            } else {
                BrowserFolderOrganizationMenuContent(menu: self)
                BrowserSidebarSelectionMenu(item: .folder(folder.id), browser: browser)
            }
        }
        .crestMenuActionLabelStyle()
    }
}
