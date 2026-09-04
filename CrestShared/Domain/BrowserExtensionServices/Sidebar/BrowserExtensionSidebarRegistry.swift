import Foundation

/// Runtime options for one extension in one Space. Only a tab-owned path
/// creates a separate document, including when it equals the default path.
struct BrowserExtensionSidebarRegistry: Equatable, Sendable {
    let defaults: BrowserExtensionSidebarDefaults
    let displayName: String
    private(set) var defaultLayer = BrowserExtensionSidebarOptions()
    private(set) var windowLayer = BrowserExtensionSidebarOptions()
    private(set) var tabLayers: [TabID: BrowserExtensionSidebarOptions] = [:]
    private var chromeTabIDs: Set<TabID> = []

    func layer(_ scope: BrowserExtensionSidebarScope) -> BrowserExtensionSidebarOptions {
        switch scope {
        case .default: defaultLayer
        case .window: windowLayer
        case .tab(let tabID): tabLayers[tabID] ?? .init()
        }
    }

    mutating func merge(_ options: BrowserExtensionSidebarOptions, at scope: BrowserExtensionSidebarScope) {
        var current = layer(scope)
        current.merge(options)
        setLayer(current, at: scope)
    }

    mutating func clearTitle(at scope: BrowserExtensionSidebarScope) {
        var current = layer(scope)
        current.title = nil
        setLayer(current, at: scope)
    }

    /// Chrome seeds a new default layer from the manifest, but a new tab layer
    /// gets only enabled=true. A missing tab path does not inherit the global
    /// resource (SidePanelService::SetOptions/GetOptions at the pinned revision).
    mutating func mergeChrome(_ options: BrowserExtensionSidebarOptions, for tab: TabID?) {
        let scope = tab.map(BrowserExtensionSidebarScope.tab) ?? .default
        if layer(scope) == .init() {
            var initial = BrowserExtensionSidebarOptions(isEnabled: true)
            if tab == nil { initial.path = defaults.path }
            initial.merge(options)
            setLayer(initial, at: scope)
        } else {
            merge(options, at: scope)
        }
        if let tab { chromeTabIDs.insert(tab) }
    }

    mutating func clearIcon(at scope: BrowserExtensionSidebarScope) {
        var current = layer(scope)
        current.icon = nil
        setLayer(current, at: scope)
    }

    func resolved(for tabID: TabID?) -> BrowserExtensionSidebarResolvedOptions {
        resolved(at: tabID.map(BrowserExtensionSidebarScope.tab) ?? .window)
    }

    func resolved(at requestedScope: BrowserExtensionSidebarScope) -> BrowserExtensionSidebarResolvedOptions {
        var options = BrowserExtensionSidebarOptions(
            path: defaults.path ?? "", isEnabled: true,
            title: defaults.title ?? displayName, icon: defaults.icon
        )
        options.merge(defaultLayer)
        var scope: BrowserExtensionSidebarScope = .default
        if requestedScope != .default {
            options.merge(windowLayer)
            if windowLayer.path != nil { scope = .window }
        }
        if case .tab(let tabID) = requestedScope, let tab = tabLayers[tabID] {
            options.merge(tab)
            if chromeTabIDs.contains(tabID), tab.path == nil { options.path = "" }
            if tab.path != nil { scope = .tab(tabID) }
        }
        return .init(
            path: options.path ?? "", isEnabled: options.isEnabled ?? true,
            title: options.title ?? displayName, icon: options.icon, scope: scope
        )
    }

    mutating func repair(liveTabs: Set<TabID>) {
        tabLayers = tabLayers.filter { liveTabs.contains($0.key) }
        chromeTabIDs.formIntersection(liveTabs)
    }

    private mutating func setLayer(
        _ options: BrowserExtensionSidebarOptions, at scope: BrowserExtensionSidebarScope
    ) {
        switch scope {
        case .default: defaultLayer = options
        case .window: windowLayer = options
        case .tab(let tabID): tabLayers[tabID] = options
        }
    }
}
