import SwiftUI

/// What a folder or group offers, the same from its context menu and from the
/// `…` button at its header's trailing edge.
struct BrowserFolderOrganizationMenu: View {

    let folder: FolderStateModel
    let context: BrowserSidebarListContext
    let assignment: BrowserFolderRuntimeAssignment
    let createNestedFolder: () -> Void
    let renameFolder: () -> Void
    let changeColor: () -> Void
    let changeIcon: () -> Void
    let deleteFolder: () -> Void

    @Environment(\.browserInteractionCapabilities) private var capabilities

    init(
        folder: FolderStateModel, context: BrowserSidebarListContext, assignment: BrowserFolderRuntimeAssignment,
        createNestedFolder: @escaping () -> Void, renameFolder: @escaping () -> Void,
        changeColor: @escaping () -> Void, changeIcon: @escaping () -> Void, deleteFolder: @escaping () -> Void
    ) {
        self.folder = folder
        self.context = context
        self.assignment = assignment
        self.createNestedFolder = createNestedFolder
        self.renameFolder = renameFolder
        self.changeColor = changeColor
        self.changeIcon = changeIcon
        self.deleteFolder = deleteFolder
    }

    /// The menu of the folder `configuration` draws, raising its presentations
    /// through `interaction`.
    init(configuration: BrowserFolderGroupConfiguration, interaction: BrowserFolderGroupInteractionContext) {
        self.init(
            folder: configuration.folder, context: configuration.context,
            assignment: configuration.folderRuntimeAssignment,
            createNestedFolder: interaction.beginCreatingChild,
            renameFolder: interaction.beginRenaming,
            changeColor: { interaction.isChoosingColor.wrappedValue = true },
            changeIcon: { interaction.isChoosingIcon.wrappedValue = true },
            // A folder that takes what it holds along asks first; a group's
            // tabs stay where they are, so it goes at once.
            deleteFolder: {
                if configuration.folder.kind.asksBeforeDeleting {
                    interaction.isConfirmingDeletion.wrappedValue = true
                } else {
                    configuration.browser.deleteFolder(
                        configuration.folder.id, matching: configuration.folderRuntimeAssignment.spaceAssignment)
                }
            })
    }

    var body: some View {
        Group {
            if capabilities.allowsMultiSelection,
                let request = BrowserSidebarSelection.capture(for: .folder(folder.id), in: context.browser)
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
