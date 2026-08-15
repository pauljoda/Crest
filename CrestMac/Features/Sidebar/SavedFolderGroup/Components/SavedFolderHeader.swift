import SwiftUI
import UniformTypeIdentifiers

struct SavedFolderHeader: View {
    let configuration: SavedFolderGroupConfiguration
    let interaction: SavedFolderGroupInteractionContext

    private var folder: SavedFolder { configuration.folder }

    var body: some View {
        SavedFolderHeaderControl(
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
        .crestHoverSurface(cornerRadius: CrestLayout.sidebarControlCornerRadius)
        .padding(.horizontal, CrestSpacing.small)
        .browserFolderDraggable(
            folder: folder,
            profileID: configuration.profileID,
            spaceID: configuration.spaceID,
            dragState: configuration.browser.folderDragState,
            reorder: BrowserSidebarReorderContext(
                browser: configuration.browser,
                spaceAccess: configuration.spaceAccess
            ),
            isEnabled: interaction.editingFolderRequest.wrappedValue
                != configuration.folderRuntimeAssignment
                && configuration.isCurrentAndUnlocked
        )
        .overlay {
            BrowserFolderNestDropHighlight(
                location: configuration.folderInsideDropLocation,
                dragState: configuration.browser.folderDragState,
                isTargeted: interaction.isDropTargeted.wrappedValue
            )
        }
    }
}

#Preview("Saved Folder Header") {
    @Previewable @State var isExpanded = true
    @Previewable @State var editingFolderRequest: BrowserFolderRuntimeAssignment? = nil
    @Previewable @State var isDropTargeted = false
    @Previewable @State var visibility =
        BrowserCollapsedFolderTabVisibilityState()
    @Previewable @FocusState var isTitleFocused: Bool

    let configuration = SavedFolderGroupPreviewFixture.configuration()
    SavedFolderHeader(
        configuration: configuration,
        interaction: SavedFolderGroupPreviewFixture.interaction(
            isExpanded: $isExpanded,
            editingFolderRequest: $editingFolderRequest,
            isDropTargeted: $isDropTargeted,
            collapsedTabVisibility: $visibility,
            isTitleFocused: $isTitleFocused
        )
    )
    .frame(width: BrowserChromeLayout.sidebarIdealWidth)
}
