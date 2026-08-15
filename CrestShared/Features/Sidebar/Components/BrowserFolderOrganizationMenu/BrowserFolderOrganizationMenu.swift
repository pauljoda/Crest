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

#Preview("Folder Organization Menu", traits: .sizeThatFitsLayout) {
    let fixture = BrowserSidebarInteractionPreviewFixture()

    Menu("Open Folder Actions", systemImage: fixture.folder.symbol) {
        BrowserFolderOrganizationMenu(
            folder: fixture.folder,
            assignment: fixture.folderAssignment,
            browser: fixture.browser,
            spaceAccess: fixture.spaceAccess,
            createNestedFolder: {},
            renameFolder: {},
            changeColor: {},
            deleteFolder: {}
        )
    }
    .padding()
}
