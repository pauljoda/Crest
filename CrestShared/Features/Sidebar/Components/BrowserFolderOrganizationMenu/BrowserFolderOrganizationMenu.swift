import SwiftUI

struct BrowserFolderOrganizationMenu: View {
    let folder: SavedFolder
    let assignment: BrowserFolderRuntimeAssignment
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let createNestedFolder: () -> Void
    let renameFolder: () -> Void
    let changeColor: () -> Void
    let deleteFolder: () -> Void

    var body: some View {
        BrowserFolderOrganizationMenuContent(menu: self)
    }
}
