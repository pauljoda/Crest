import SwiftUI

struct BrowserSidebarSelectionMenu: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let item: BrowserSelectionItemID
    let browser: BrowserStore
    @Environment(\.browserInteractionCapabilities) private var capabilities

    var body: some View {
        if capabilities.allowsMultiSelection {
            Divider()
            Button("Add to Selection") {
                browser.tabMultiSelection.click(
                    item,
                    units: BrowserSidebarSelection.itemUnits(
                        in: browser, reorder: sidebarInteraction.sidebarReorderState), command: true)
            }
            Button {
                browser.tabMultiSelection.selectAll(
                    units: BrowserSidebarSelection.itemUnits(
                        in: browser, reorder: sidebarInteraction.sidebarReorderState))
            } label: {
                switch item {
                case .tab: Text("Select All Tabs")
                case .folder: Text("Select All Items")
                }
            }
        }
    }
}
