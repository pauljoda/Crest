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
            let menuItems: [BrowserExtensionToolbarMenuItem] =
                tab.map { tab in
                    let nativeItems = context.menuItems(for: tab)
                    let filteredItems: [NSMenuItem]
                    if runtime.internallyGrantedPermissions(
                        extensionID: summary.id,
                        in: spaceID
                    ).contains("nativeMessaging") {
                        let clientID = BrowserExtensionServiceClientID.scoped(
                            extensionID: summary.id,
                            spaceID: spaceID
                        )
                        let definitions =
                            webpageMenuRegistry.definitions(for: clientID)
                        filteredItems =
                            (try? BrowserExtensionWebpageMenuPolicy.tabItems(
                                nativeItems,
                                definitions: definitions,
                                pageURL: tab.url(for: context)
                            )) ?? []
                    } else {
                        filteredItems = nativeItems
                    }
                    return filteredItems.map {
                        BrowserExtensionToolbarMenuItem(item: $0)
                    }
                } ?? []
            return BrowserExtensionToolbarAction(
                id: summary.id,
                displayName: summary.displayName,
                label: action.label,
                badgeText: action.badgeText,
                icon: action.icon(for: CGSize(width: 20, height: 20)),
                isEnabled: action.isEnabled,
                isPinned: summary.isPinned,
                isPopupLoading:
                    tabWindowCoordinator.isActionPopupLoading(for: context),
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
        tabWindowCoordinator.noteUserGesture(for: toolbarAction.context)
        if tabWindowCoordinator.performSidebarAction(for: toolbarAction.context, invocation: .action) { return }
        guard toolbarAction.action.presentsPopup else {
            toolbarAction.context.performAction(
                for: toolbarAction.tab
            )
            return
        }
        guard
            !tabWindowCoordinator.isActionPopupLoading(
                for: toolbarAction.context
            )
        else {
            return
        }
        if let tab = toolbarAction.tab {
            toolbarAction.context.userGesturePerformed(in: tab)
        }
        tabWindowCoordinator.requestActionPopup(
            toolbarAction.action,
            for: toolbarAction.context,
            anchor: popupAnchor
        )
    }

    func prepare(_ toolbarAction: BrowserExtensionToolbarAction) {
        guard
            toolbarAction.isEnabled,
            toolbarAction.action.presentsPopup
        else {
            return
        }
        tabWindowCoordinator.prepareActionPopup(
            toolbarAction.action,
            for: toolbarAction.context
        )
    }

    func perform(
        _ menuItem: BrowserExtensionToolbarMenuItem,
        for toolbarAction: BrowserExtensionToolbarAction
    ) {
        tabWindowCoordinator.noteUserGesture(for: toolbarAction.context)
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
