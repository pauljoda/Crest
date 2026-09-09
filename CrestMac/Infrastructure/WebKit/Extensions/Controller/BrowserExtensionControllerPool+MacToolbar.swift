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

    func pinnedActionPresentations(in spaceID: SpaceID, tabID: TabID?) -> [BrowserExtensionActionPresentation] {
        _ = actionRevision
        return toolbarController.pinnedActionPresentations(
            summaries: extensions(in: spaceID), in: spaceID, tabID: tabID)
    }

    /// Layout needs presence, without loading artwork or constructing menus.
    func hasPinnedToolbarActions(in spaceID: SpaceID, tabID: TabID?) -> Bool {
        _ = actionRevision
        let tab = tabID.flatMap { tabWindowCoordinator.tab(for: $0, in: spaceID) }
        return extensions(in: spaceID).contains { summary in
            summary.isEnabled && summary.isPinned
                && runtimeContextController.loadedContext(extensionID: summary.id, in: spaceID)?.action(for: tab) != nil
        }
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

    func prepare(_ toolbarAction: BrowserExtensionToolbarAction) {
        toolbarController.prepare(toolbarAction)
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
