import SwiftUI

struct BrowserTabOrganizationMenu: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

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

    @Environment(\.browserInteractionCapabilities) private var capabilities

    var body: some View {
        Group {
            if capabilities.allowsMultiSelection,
                let request = BrowserSidebarSelection.request(
                    for: tab.id, browser: browser, reorder: sidebarInteraction.sidebarReorderState)
            {
                BrowserTabBatchMenu(request: request, browser: browser, spaceAccess: spaceAccess, unload: unload)
            } else {
                BrowserTabOrganizationMenuContent(menu: self)
                BrowserSidebarSelectionMenu(item: .tab(tab.id), browser: browser)
            }
        }
        .crestMenuActionLabelStyle()
    }
}
