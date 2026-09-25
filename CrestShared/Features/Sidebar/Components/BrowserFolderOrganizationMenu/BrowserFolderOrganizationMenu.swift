import SwiftUI

struct BrowserFolderOrganizationMenu: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let folder: FolderStateModel
    let context: BrowserSidebarListContext
    let assignment: BrowserFolderRuntimeAssignment
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
                    for: .folder(folder.id), browser: context.browser,
                    reorder: sidebarInteraction.sidebarReorderState)
            {
                BrowserTabBatchMenu(request: request, browser: context.browser, spaceAccess: context.spaceAccess)
            } else {
                BrowserFolderOrganizationMenuContent(menu: self)
                BrowserSidebarSelectionMenu(item: .folder(folder.id), browser: context.browser)
            }
        }
        .crestMenuActionLabelStyle()
    }
}
