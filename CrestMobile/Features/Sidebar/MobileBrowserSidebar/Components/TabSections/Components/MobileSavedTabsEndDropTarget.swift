import SwiftUI
import UniformTypeIdentifiers

struct MobileSavedTabsEndDropTarget: View {
    let tabs: [BrowserTab]
    let browser: BrowserStore
    @Binding var isTargeted: Bool
    let moveTab: (BrowserTabDragItem, TabID?) -> Bool
    let moveFolder: (BrowserFolderDragItem, BrowserFolderDropLocation) -> Bool

    var body: some View {
        Color.clear
            .frame(height: MobileSidebarDropTargetPolicy.sectionEndTargetHeight)
            .contentShape(.rect)
            .overlay(alignment: .top) {
                if BrowserTabRowIndicatorOwnershipPolicy.showsSectionEndIndicator(
                    hasVisibleRows: !tabs.isEmpty
                ) {
                    BrowserTabDropIndicator(
                        location: tabLocation,
                        dragState: browser.tabDragState,
                        isTargeted: isTargeted
                    )
                }
            }
            .overlay(alignment: .bottom) {
                BrowserFolderDropIndicator(
                    location: folderLocation,
                    dragState: browser.folderDragState,
                    isTargeted: isTargeted
                )
            }
            .accessibilityHidden(true)
    }

    private var tabLocation: BrowserTabDropLocation {
        BrowserTabDropLocation(
            placement: .saved,
            folderID: nil,
            beforeTabID: nil
        )
    }

    private var folderLocation: BrowserFolderDropLocation {
        BrowserFolderDropLocation(parentID: nil, beforeSiblingID: nil)
    }
}
