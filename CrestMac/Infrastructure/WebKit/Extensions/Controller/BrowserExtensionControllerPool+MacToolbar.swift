import Foundation
import WebKit

extension BrowserExtensionControllerPool {
    func toolbarActions(
        in spaceID: SpaceID,
        tabID: TabID?
    ) -> [BrowserExtensionToolbarAction] {
        _ = actionRevision
        return toolbarController.toolbarActions(
            summaries: extensions(in: spaceID),
            in: spaceID,
            tabID: tabID
        )
    }

    func perform(
        _ toolbarAction: BrowserExtensionToolbarAction,
        popupAnchor: BrowserExtensionPopupAnchor? = nil
    ) {
        toolbarController.perform(
            toolbarAction,
            popupAnchor: popupAnchor
        )
    }

    func perform(
        _ menuItem: BrowserExtensionToolbarMenuItem,
        for toolbarAction: BrowserExtensionToolbarAction
    ) {
        toolbarController.perform(menuItem, for: toolbarAction)
    }

    func openOptionsPage(
        extensionID: String,
        in spaceID: SpaceID
    ) {
        toolbarController.openOptionsPage(
            extensionID: extensionID,
            in: spaceID
        )
    }
}
