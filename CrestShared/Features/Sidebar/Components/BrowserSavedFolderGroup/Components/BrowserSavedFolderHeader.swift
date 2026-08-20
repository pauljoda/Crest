import SwiftUI

/// The folder's own row: the control a reader opens it with, wearing the
/// surface, the drag source, and the drop feedback that belong to the folder
/// rather than to its contents.
struct BrowserSavedFolderHeader: View {
    let configuration: BrowserSavedFolderGroupConfiguration
    let interaction: BrowserSavedFolderGroupInteractionContext

    private var folder: SavedFolder { configuration.folder }

    var body: some View {
        BrowserSavedFolderHeaderControl(
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
        .crestHoverSurface(
            isSelected: BrowserFolderRowPresentationPolicy.showsDropHighlight(
                isTargeted: interaction.isDropTargeted.wrappedValue,
                isTabDragging: configuration.browser.tabDragState.item != nil
            ),
            cornerRadius: CrestLayout.sidebarControlCornerRadius
        )
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
        .modifier(
            BrowserSavedFolderHeaderDropFeedback(
                configuration: configuration,
                isTargeted: interaction.isDropTargeted.wrappedValue
            )
        )
    }
}

/// What a folder being dragged over this header says about where it would
/// land.
///
/// The two answers are alternatives, not layers. Where the shell draws its
/// insertion lines on the rows themselves, a folder header carries the line
/// for the seam above it, matching the tab rows in the same list. Where the
/// section's zone carries insertion instead, the header is free to say the one
/// thing a zone cannot: that releasing *here* files the folder inside this one.
private struct BrowserSavedFolderHeaderDropFeedback: ViewModifier {
    let configuration: BrowserSavedFolderGroupConfiguration
    let isTargeted: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if configuration.capabilities.showsRowDropIndicators {
            content.overlay(alignment: .bottom) {
                BrowserFolderDropIndicator(
                    location: configuration.folderDropLocation,
                    dragState: configuration.browser.folderDragState,
                    isTargeted: isTargeted
                )
            }
        } else {
            content.overlay {
                BrowserFolderNestDropHighlight(
                    location: configuration.folderInsideDropLocation,
                    dragState: configuration.browser.folderDragState,
                    isTargeted: isTargeted
                )
            }
        }
    }
}
