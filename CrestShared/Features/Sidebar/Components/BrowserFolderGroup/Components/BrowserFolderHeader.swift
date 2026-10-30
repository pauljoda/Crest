import SwiftUI

/// The folder's own row: the control a reader opens it with, wearing the
/// surface, the drag source, and the drop feedback that belong to the folder
/// rather than to its contents.
struct BrowserFolderHeader: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let configuration: BrowserFolderGroupConfiguration
    let interaction: BrowserFolderGroupInteractionContext

    private var folder: FolderStateModel { configuration.folder }
    private var tabScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }

    var body: some View {
        BrowserFolderHeaderControl(
            configuration: configuration,
            interaction: interaction
        )
        .modifier(BrowserFolderHeaderAccessibility(folder: folder, isExpanded: interaction.isExpanded.wrappedValue))
        .modifier(BrowserFolderSelectionAccessibility(folderID: folder.id, browser: configuration.browser))
        // Inside the folder's padding, as a Split View's header is inside its own.
        .padding(.horizontal, BrowserSidebarMetrics.layerInset + BrowserSidebarMetrics.containerPadding)
        .padding(.vertical, BrowserSidebarDensity(tabScale).rowSeparation() / 2)
        .modifier(
            BrowserTabSelectionTarget(
                tabID: nil, browser: configuration.browser,
                assignment: configuration.folderRuntimeAssignment.spaceAssignment,
                isEnabled: configuration.isAvailableForDisplay
                    && interaction.editingFolderRequest.wrappedValue != configuration.folderRuntimeAssignment,
                folderID: folder.id)
        )
        .browserFolderDraggable(
            folder: folder,
            profileID: configuration.profileID,
            spaceID: configuration.spaceID,
            dragState: sidebarInteraction.folderDragState,
            reorder: BrowserSidebarReorderContext(
                browser: configuration.browser,
                spaceAccess: configuration.spaceAccess,
                state: sidebarInteraction.sidebarReorderState
            ),
            isEnabled: interaction.editingFolderRequest.wrappedValue
                != configuration.folderRuntimeAssignment
                && configuration.isAvailableForDisplay,
            requiresSelectedSpace: true
        )
        // The one thing a section's zone cannot say: that releasing *here* files
        // the lifted folder inside this one rather than beside it. The seam
        // above the header is already drawn by the row's own reorder indicator,
        // on every shell, so the header carries only the nesting answer.
        .overlay {
            BrowserFolderNestDropHighlight(
                state: sidebarInteraction.sidebarReorderState, target: .folder(folder.id), depth: configuration.depth)
        }
    }
}

/// A folder's header reads as one folder control. A header Tidy made labels
/// its title and its close control apart instead, so the label here would
/// cover both.
private struct BrowserFolderHeaderAccessibility: ViewModifier {
    let folder: FolderStateModel
    let isExpanded: Bool

    func body(content: Content) -> some View {
        if folder.isTidyHeader {
            content
        } else {
            content
                .accessibilityLabel("\(folder.shownTitle) folder")
                .accessibilityValue(BrowserChromeAccessibility.folderValue(isExpanded: isExpanded))
                .accessibilityHint(isExpanded ? "Collapses this folder" : "Expands this folder")
        }
    }
}
