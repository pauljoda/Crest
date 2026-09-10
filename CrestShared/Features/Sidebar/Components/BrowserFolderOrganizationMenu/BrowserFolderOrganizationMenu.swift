import SwiftUI

struct BrowserFolderOrganizationMenu: View {
    let folder: BrowserFolder
    let assignment: BrowserFolderRuntimeAssignment
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let createNestedFolder: () -> Void
    let renameFolder: () -> Void
    let changeColor: () -> Void
    let deleteFolder: () -> Void

    var body: some View {
        Group {
            if let request = BrowserSidebarSelection.request(for: .folder(folder.id), browser: browser) {
                BrowserTabBatchMenu(request: request, browser: browser, spaceAccess: spaceAccess)
            } else {
                BrowserFolderOrganizationMenuContent(menu: self)
                Divider()
                Button("Add to Selection") {
                    browser.tabMultiSelection.click(
                        .folder(folder.id), units: BrowserSidebarSelection.itemUnits(in: browser), command: true)
                }
            }
        }
        .crestMenuActionLabelStyle()
    }
}
