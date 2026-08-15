import AppKit
import WebKit

extension BrowserExtensionToolbarController {
    func toolbarActions(
        summaries: [BrowserExtensionSummary],
        in spaceID: SpaceID,
        tabID: TabID?
    ) -> [BrowserExtensionToolbarAction] {
        let tab = tabID.flatMap {
            tabWindowCoordinator.tab(for: $0, in: spaceID)
        }
        return summaries.compactMap { summary in
            guard summary.isEnabled,
                let context = runtime.loadedContext(
                    extensionID: summary.id,
                    in: spaceID
                ),
                let action = context.action(for: tab)
            else {
                return nil
            }
            let commands = context.commands.map {
                BrowserExtensionToolbarCommand(
                    id: "\(summary.id).\($0.id)",
                    title: $0.title,
                    command: $0
                )
            }
            let menuItems =
                tab.map {
                    context.menuItems(for: $0).map(
                        BrowserExtensionToolbarMenuItem.init(item:)
                    )
                } ?? []
            return BrowserExtensionToolbarAction(
                id: summary.id,
                displayName: summary.displayName,
                label: action.label,
                badgeText: action.badgeText,
                icon: action.icon(for: CGSize(width: 20, height: 20)),
                isEnabled: action.isEnabled,
                isPinned: summary.isPinned,
                action: action,
                context: context,
                tab: tab,
                commands: commands,
                menuItems: menuItems
            )
        }
    }

    func perform(
        _ toolbarAction: BrowserExtensionToolbarAction,
        popupAnchor: BrowserExtensionPopupAnchor?
    ) {
        guard toolbarAction.isEnabled else { return }
        if let tab = toolbarAction.tab {
            toolbarAction.context.userGesturePerformed(in: tab)
        }
        guard toolbarAction.action.presentsPopup else {
            toolbarAction.context.performAction(
                for: toolbarAction.tab
            )
            return
        }
        tabWindowCoordinator.presentActionPopup(
            toolbarAction.action,
            anchor: popupAnchor
        )
    }

    func perform(
        _ menuItem: BrowserExtensionToolbarMenuItem,
        for toolbarAction: BrowserExtensionToolbarAction
    ) {
        if let tab = toolbarAction.tab {
            toolbarAction.context.userGesturePerformed(in: tab)
        }
        guard let action = menuItem.item.action else { return }
        NSApp.sendAction(
            action,
            to: menuItem.item.target,
            from: menuItem.item
        )
    }

    func openOptionsPage(extensionID: String, in spaceID: SpaceID) {
        guard
            let context = runtime.loadedContext(
                extensionID: extensionID,
                in: spaceID
            )
        else {
            return
        }
        tabWindowCoordinator.presentOptionsPage(for: context) { _ in }
    }
}
