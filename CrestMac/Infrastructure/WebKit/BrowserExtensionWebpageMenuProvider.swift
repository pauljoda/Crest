import AppKit
import Foundation
import WebKit

@MainActor
final class BrowserExtensionWebpageMenuProvider {
    private let extensionControllerPool: BrowserExtensionControllerPool

    init(extensionControllerPool: BrowserExtensionControllerPool) {
        self.extensionControllerPool = extensionControllerPool
    }

    func items(
        for tabID: TabID,
        in spaceID: SpaceID,
        context webpageContext: BrowserExtensionWebpageMenuContext
    ) -> [NSMenuItem] {
        guard let tab = extensionControllerPool.extensionTab(tabID, in: spaceID)
        else { return [] }
        let enabledSummaries = Dictionary(
            uniqueKeysWithValues: (extensionControllerPool.summariesBySpace[spaceID] ?? [])
                .filter(\.isEnabled)
                .map { ($0.id, $0) }
        )
        return extensionControllerPool.runtimeContextController
            .contexts(in: spaceID)
            .compactMap { entry -> Contribution? in
                let (extensionID, extensionContext) = entry
                guard let summary = enabledSummaries[extensionID]
                else { return nil }
                let clientID = BrowserExtensionServiceClientID.scoped(
                    extensionID: extensionID,
                    spaceID: spaceID
                )
                let definitions = extensionControllerPool.webpageMenuRegistry
                    .definitions(for: clientID)
                guard !definitions.isEmpty,
                    let mapped =
                        try? BrowserExtensionWebpageMenuPolicy
                        .nativeItems(
                            extensionContext.menuItems(for: tab),
                            definitions: definitions
                        )
                else { return nil }
                let matchingIDs = Set(
                    BrowserExtensionWebpageMenuPolicy.matchingDefinitions(
                        definitions,
                        context: webpageContext
                    ).map(\.id)
                )
                let items = mapped.compactMap { mappedItem in
                    self.item(
                        from: mappedItem,
                        matchingIDs: matchingIDs,
                        webpageContext: webpageContext,
                        clientID: clientID,
                        extensionContext: extensionContext,
                        tab: tab
                    )
                }
                guard !items.isEmpty else { return nil }
                if items.count == 1 {
                    return Contribution(
                        sortKey: summary.displayName,
                        items: items
                    )
                }
                let parent = NSMenuItem(
                    title: summary.displayName,
                    action: nil,
                    keyEquivalent: ""
                )
                let submenu = NSMenu(title: summary.displayName)
                submenu.items = items
                parent.submenu = submenu
                return Contribution(
                    sortKey: summary.displayName,
                    items: [parent]
                )
            }
            .sorted { (lhs: Contribution, rhs: Contribution) in
                lhs.sortKey.localizedStandardCompare(rhs.sortKey)
                    == .orderedAscending
            }
            .flatMap(\.items)
    }

    private func item(
        from mapped: BrowserExtensionWebpageNativeMenuItem,
        matchingIDs: Set<String>,
        webpageContext: BrowserExtensionWebpageMenuContext,
        clientID: BrowserExtensionServiceClientID,
        extensionContext: WKWebExtensionContext,
        tab: BrowserExtensionTabAdapter
    ) -> NSMenuItem? {
        guard matchingIDs.contains(mapped.definition.id),
            let clone = mapped.nativeItem.copy() as? NSMenuItem
        else { return nil }
        clone.title = BrowserExtensionWebpageMenuPolicy.title(
            for: mapped.definition,
            context: webpageContext
        )
        clone.isEnabled =
            mapped.definition.enabled
            && mapped.nativeItem.isEnabled
        let children = mapped.children.compactMap { child in
            item(
                from: child,
                matchingIDs: matchingIDs,
                webpageContext: webpageContext,
                clientID: clientID,
                extensionContext: extensionContext,
                tab: tab
            )
        }
        if !children.isEmpty {
            let submenu = NSMenu(title: clone.title)
            submenu.items = children
            clone.submenu = submenu
        } else if mapped.children.isEmpty {
            clone.submenu = nil
        } else {
            return nil
        }
        guard mapped.nativeItem.action != nil else { return clone }
        let action = BrowserExtensionWebpageMenuAction(
            menuItemID: mapped.definition.id,
            webpageContext: webpageContext,
            clientID: clientID,
            registry: extensionControllerPool.webpageMenuRegistry,
            extensionContext: extensionContext,
            tab: tab,
            nativeItem: mapped.nativeItem
        )
        clone.target = action
        clone.action = #selector(
            BrowserExtensionWebpageMenuAction.performExtensionMenuItem(_:)
        )
        clone.representedObject = action
        return clone
    }

    private struct Contribution {
        let sortKey: String
        let items: [NSMenuItem]
    }
}

@MainActor
private final class BrowserExtensionWebpageMenuAction: NSObject {
    private let menuItemID: String
    private let webpageContext: BrowserExtensionWebpageMenuContext
    private let clientID: BrowserExtensionServiceClientID
    private let registry: BrowserExtensionWebpageMenuRegistry
    private let extensionContext: WKWebExtensionContext
    private let tab: BrowserExtensionTabAdapter
    private let nativeItem: NSMenuItem

    init(
        menuItemID: String,
        webpageContext: BrowserExtensionWebpageMenuContext,
        clientID: BrowserExtensionServiceClientID,
        registry: BrowserExtensionWebpageMenuRegistry,
        extensionContext: WKWebExtensionContext,
        tab: BrowserExtensionTabAdapter,
        nativeItem: NSMenuItem
    ) {
        self.menuItemID = menuItemID
        self.webpageContext = webpageContext
        self.clientID = clientID
        self.registry = registry
        self.extensionContext = extensionContext
        self.tab = tab
        self.nativeItem = nativeItem
    }

    @objc(performExtensionWebpageMenuItem:)
    func performExtensionMenuItem(_: NSMenuItem) {
        registry.publishClick(
            menuItemID: menuItemID,
            context: webpageContext,
            tabID: tab.tabID,
            for: clientID
        )
        extensionContext.userGesturePerformed(in: tab)
        guard let action = nativeItem.action else { return }
        NSApp.sendAction(action, to: nativeItem.target, from: nativeItem)
    }
}
