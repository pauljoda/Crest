import SwiftUI

/// The landing band the unfiled saved run keeps at its end.
///
/// The tab half matches the current run's band: a shell that draws its drop
/// feedback on the rows needs somewhere to aim past the last one, and an empty
/// unfiled run needs a region at all. The folder half is what makes the band
/// the place a dragged folder lands beside the last root folder rather than
/// inside it.
struct BrowserSavedTabsEndDropTarget: View {
    let tabs: [BrowserTab]
    let browser: BrowserStore
    let capabilities: BrowserInteractionCapabilities

    var body: some View {
        Color.clear
            .frame(height: bandHeight)
            .contentShape(.rect)
            .overlay(alignment: .top) {
                if BrowserTabRowIndicatorOwnershipPolicy.showsSectionEndIndicator(
                    hasVisibleRows: !tabs.isEmpty
                ) {
                    BrowserTabDropIndicator(
                        location: tabLocation,
                        dragState: browser.tabDragState,
                        isTargeted: false
                    )
                }
            }
            .overlay(alignment: .bottom) {
                BrowserFolderDropIndicator(
                    location: folderLocation,
                    dragState: browser.folderDragState,
                    isTargeted: false
                )
            }
            .accessibilityHidden(true)
    }

    private var bandHeight: CGFloat {
        BrowserSidebarInteractionPolicy.tabListMetrics(capabilities)
            .sectionEndBandHeight
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
