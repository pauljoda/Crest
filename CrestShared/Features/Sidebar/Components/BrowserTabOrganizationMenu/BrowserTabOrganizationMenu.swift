import SwiftUI

struct BrowserTabOrganizationMenu: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let tab: TabStateModel
    let context: BrowserSidebarListContext
    let assignment: BrowserTabRuntimeAssignment
    var isLoaded = true
    var renameTab: (() -> Void)? = nil
    var changeIcon: (() -> Void)? = nil

    @Environment(\.browserInteractionCapabilities) private var capabilities

    var body: some View {
        Group {
            if capabilities.allowsMultiSelection,
                let request = BrowserSidebarSelection.request(
                    for: tab.id, browser: context.browser, reorder: sidebarInteraction.sidebarReorderState)
            {
                BrowserTabBatchMenu(
                    request: request, browser: context.browser, spaceAccess: context.spaceAccess,
                    unload: { context.unload($0) })
            } else {
                BrowserTabOrganizationMenuContent(menu: self)
                BrowserSidebarSelectionMenu(item: .tab(tab.id), browser: context.browser)
            }
        }
        .crestMenuActionLabelStyle()
    }
}
