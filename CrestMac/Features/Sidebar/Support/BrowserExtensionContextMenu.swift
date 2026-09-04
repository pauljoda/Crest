import AppKit

/// Builds and presents the secondary-click menu for an extension's toolbar
/// action. WebKit hands Crest real `NSMenuItem`s for the extension's own
/// entries, but they are rebuilt here rather than installed directly so every
/// invocation goes back through the controller pool, which reports the user
/// gesture that `activeTab` depends on before running the item.
@MainActor
final class BrowserExtensionContextMenu: NSObject {
    private var handlers: [() -> Void] = []

    static func present(
        for action: BrowserExtensionToolbarAction,
        pool: BrowserExtensionControllerPool,
        spaceID: SpaceID,
        anchor: BrowserExtensionPopupAnchor?,
        manageExtensions: (() -> Void)? = nil
    ) {
        // The builder owns the menu item handlers and `NSMenuItem.target` is a
        // weak reference, so it has to outlive the tracking loop below.
        let builder = BrowserExtensionContextMenu()
        let menu = builder.makeMenu(
            for: action,
            pool: pool,
            spaceID: spaceID,
            manageExtensions: manageExtensions
        )
        guard
            let hostView = anchor?.contentView(
                fallbackWindow: NSApp.keyWindow
            )
        else {
            return
        }
        let windowPoint =
            hostView.window?.convertPoint(fromScreen: anchor?.screenPoint ?? .zero)
            ?? anchor?.screenPoint
            ?? .zero
        menu.popUp(
            positioning: nil,
            at: hostView.convert(windowPoint, from: nil),
            in: hostView
        )
    }

    func makeMenu(
        for action: BrowserExtensionToolbarAction,
        pool: BrowserExtensionControllerPool,
        spaceID: SpaceID,
        manageExtensions: (() -> Void)? = nil
    ) -> NSMenu {
        let menu = NSMenu(title: action.displayName)
        menu.autoenablesItems = false

        for menuItem in action.menuItems {
            menu.addItem(item(for: menuItem, in: action, pool: pool))
        }
        if !action.menuItems.isEmpty {
            menu.addItem(.separator())
        }

        for command in action.commands {
            menu.addItem(
                item(title: command.title, isEnabled: action.isEnabled) {
                    pool.perform(command, in: spaceID)
                }
            )
        }
        if !action.commands.isEmpty {
            menu.addItem(.separator())
        }

        if action.context.webExtension.hasOptionsPage {
            menu.addItem(
                item(title: String(localized: "Extension Settings…")) {
                    pool.openOptionsPage(
                        extensionID: action.id,
                        in: spaceID
                    )
                }
            )
        }
        if pool.tabWindowCoordinator.sidebarIsAvailable(for: action.context) {
            menu.addItem(
                item(
                    title: pool.tabWindowCoordinator.sidebarIsOpen(for: action.context)
                        ? String(localized: "Hide Side Panel") : String(localized: "Show Side Panel")
                ) {
                    pool.tabWindowCoordinator.performSidebarAction(for: action.context, invocation: .menu)
                })
        }
        menu.addItem(
            item(
                title: action.isPinned
                    ? String(localized: "Unpin from Sidebar")
                    : String(localized: "Pin to Sidebar")
            ) {
                pool.setPinned(
                    !action.isPinned,
                    extensionID: action.id,
                    in: spaceID
                )
            }
        )
        if let manageExtensions {
            menu.addItem(.separator())
            menu.addItem(
                item(title: String(localized: "Manage Extensions…"), perform: manageExtensions)
            )
        }
        return menu
    }

    private func item(
        for menuItem: BrowserExtensionToolbarMenuItem,
        in action: BrowserExtensionToolbarAction,
        pool: BrowserExtensionControllerPool
    ) -> NSMenuItem {
        guard !menuItem.isSeparator else { return .separator() }
        guard menuItem.children.isEmpty else {
            let parent = NSMenuItem(
                title: menuItem.title,
                action: nil,
                keyEquivalent: ""
            )
            parent.isEnabled = menuItem.isEnabled
            let submenu = NSMenu(title: menuItem.title)
            submenu.autoenablesItems = false
            for child in menuItem.children {
                submenu.addItem(item(for: child, in: action, pool: pool))
            }
            parent.submenu = submenu
            return parent
        }
        return item(title: menuItem.title, isEnabled: menuItem.isEnabled) {
            pool.perform(menuItem, for: action)
        }
    }

    private func item(
        title: String,
        isEnabled: Bool = true,
        perform: @escaping () -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(invoke(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.isEnabled = isEnabled
        item.tag = handlers.count
        handlers.append(perform)
        return item
    }

    @objc private func invoke(_ sender: NSMenuItem) {
        guard handlers.indices.contains(sender.tag) else { return }
        handlers[sender.tag]()
    }
}
