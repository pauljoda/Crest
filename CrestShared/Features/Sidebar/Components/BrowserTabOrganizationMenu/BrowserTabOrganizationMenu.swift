import SwiftUI

struct BrowserTabOrganizationMenu: View {
    let tab: BrowserTab
    let assignment: BrowserTabRuntimeAssignment
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    var isLoaded = true
    var unload: ((TabID) -> Void)? = nil
    var pullNewIcon: (() -> Void)? = nil
    var restoreSavedLocation: (() -> Void)? = nil
    var renameTab: (() -> Void)? = nil
    var changeIcon: (() -> Void)? = nil

    var body: some View {
        Group {
            if let request = BrowserSidebarSelection.request(for: tab.id, browser: browser) {
                BrowserTabBatchMenu(request: request, browser: browser, spaceAccess: spaceAccess, unload: unload)
            } else {
                BrowserTabOrganizationMenuContent(menu: self)
                #if os(macOS)
                    Divider()
                    Button("Add to Selection") {
                        browser.tabMultiSelection.click(
                            tab.id, units: BrowserSidebarSelection.itemUnits(in: browser), command: true)
                    }
                    Button("Select All Tabs") {
                        browser.tabMultiSelection.selectAll(units: BrowserSidebarSelection.itemUnits(in: browser))
                    }
                #endif
            }
        }
        .crestMenuActionLabelStyle()
    }
}
