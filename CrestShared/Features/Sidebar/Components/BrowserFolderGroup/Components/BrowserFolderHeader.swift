import SwiftUI

/// The folder's own row: the control a reader opens it with, wearing the
/// surface, the drag source, and the drop feedback that belong to the folder
/// rather than to its contents.
struct BrowserFolderHeader: View {
    let configuration: BrowserFolderGroupConfiguration
    let interaction: BrowserFolderGroupInteractionContext

    private var folder: BrowserFolder { configuration.folder }

    var body: some View {
        BrowserFolderHeaderControl(
            configuration: configuration,
            interaction: interaction
        )
        .accessibilityLabel("\(folder.title) folder")
        .accessibilityValue(
            BrowserChromeAccessibility.folderValue(
                isExpanded: interaction.isExpanded.wrappedValue
            )
        )
        .accessibilityHint(
            interaction.isExpanded.wrappedValue
                ? "Collapses this folder"
                : "Expands this folder"
        )
        .padding(.horizontal, CrestSpacing.small)
        .browserFolderDraggable(
            folder: folder,
            profileID: configuration.profileID,
            spaceID: configuration.spaceID,
            dragState: configuration.browser.folderDragState,
            memberTabIDs: configuration.subtreeTabIDs,
            reorder: BrowserSidebarReorderContext(
                browser: configuration.browser,
                spaceAccess: configuration.spaceAccess
            ),
            isEnabled: interaction.editingFolderRequest.wrappedValue
                != configuration.folderRuntimeAssignment
                && configuration.isCurrentAndUnlocked
        )
        // The one thing a section's zone cannot say: that releasing *here* files
        // the lifted folder inside this one rather than beside it. The seam
        // above the header is already drawn by the row's own reorder indicator,
        // on every shell, so the header carries only the nesting answer.
        .overlay {
            BrowserFolderNestDropHighlight(
                isTargeted: BrowserFolderRowPresentationPolicy.showsNestOutline(
                    for: configuration.nestingLift
                )
            )
        }
    }
}
