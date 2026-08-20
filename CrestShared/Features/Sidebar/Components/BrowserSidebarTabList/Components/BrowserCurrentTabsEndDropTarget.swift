import SwiftUI

/// The landing band the current run keeps at its end.
///
/// A finger cannot aim at the seam between two rows that touch, so a shell that
/// draws its drop feedback on the rows themselves keeps a band of its own after
/// the last one. It is also the band a cleared list draws its insertion line
/// in: with no rows left it sits directly below the new-tab row, where the
/// first current tab would appear.
struct BrowserCurrentTabsEndDropTarget: View {
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
                        location: dropLocation,
                        dragState: browser.tabDragState,
                        isTargeted: false
                    )
                }
            }
            .accessibilityHidden(true)
    }

    private var bandHeight: CGFloat {
        BrowserSidebarInteractionPolicy.tabListMetrics(capabilities)
            .sectionEndBandHeight
    }

    private var dropLocation: BrowserTabDropLocation {
        BrowserTabDropLocation(
            placement: .current,
            folderID: nil,
            beforeTabID: nil
        )
    }
}
