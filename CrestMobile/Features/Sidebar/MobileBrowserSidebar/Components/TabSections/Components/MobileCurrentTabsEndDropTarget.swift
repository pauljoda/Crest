import SwiftUI
import UniformTypeIdentifiers

struct MobileCurrentTabsEndDropTarget: View {
    let tabs: [BrowserTab]
    let browser: BrowserStore
    @Binding var isTargeted: Bool
    let move: (BrowserTabDragItem, TabID?) -> Bool

    var body: some View {
        Color.clear
            .frame(height: MobileSidebarDropTargetPolicy.sectionEndTargetHeight)
            .contentShape(.rect)
            .overlay(alignment: .top) {
                if BrowserTabRowIndicatorOwnershipPolicy.showsSectionEndIndicator(
                    hasVisibleRows: !tabs.isEmpty
                ) {
                    BrowserTabDropIndicator(
                        location: dropLocation,
                        dragState: browser.tabDragState,
                        isTargeted: isTargeted
                    )
                }
            }
            .accessibilityHidden(true)
    }

    private var dropLocation: BrowserTabDropLocation {
        BrowserTabDropLocation(
            placement: .current,
            folderID: nil,
            beforeTabID: nil
        )
    }
}

#Preview("Current Tabs End Drop Target", traits: .sizeThatFitsLayout) {
    @Previewable @State var isTargeted = false
    let fixture = MobileBrowserSidebarPreviewFixture()

    MobileCurrentTabsEndDropTarget(
        tabs: [fixture.currentTab],
        browser: fixture.browser,
        isTargeted: $isTargeted,
        move: { _, _ in false }
    )
    .frame(width: 320)
    .background(.quaternary)
}
