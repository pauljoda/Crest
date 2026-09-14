import Foundation
import Observation

/// Global and tab-owned extension documents stay in their native window and
/// Space. A tab-specific resource is never presented beside a different tab.
@Observable
@MainActor
final class BrowserExtensionSidebarStore: BrowserExtensionSidebarHandling {
    private struct Registration: Equatable {
        let spaceID: SpaceID
        let baseURL: URL
        var registry: BrowserExtensionSidebarRegistry
        var behavior: BrowserExtensionSidebarBehavior
    }
    private struct Visibility: Equatable {
        var tabID: TabID?
        var isAvailable: Bool
    }

    private(set) var presentationsByWindow:
        [BrowserWindowID: [SpaceID: [BrowserExtensionSidebarScope: BrowserExtensionSidebarPresentation]]] = [:]
    private(set) var optionsRevision = 0
    @ObservationIgnored private var registrations: [BrowserExtensionServiceClientID: Registration] = [:]
    @ObservationIgnored private var visibility: [BrowserWindowID: [SpaceID: Visibility]] = [:]
    @ObservationIgnored private var visiblePanels: [BrowserWindowID: [SpaceID: BrowserExtensionSidebarPanel]] = [:]
    @ObservationIgnored private let behaviorPersistence: any BrowserExtensionSidebarBehaviorPersisting
    @ObservationIgnored private let eventHub = BrowserExtensionClientEventHub<BrowserExtensionSidebarEvent>()
    @ObservationIgnored var hostWindowResolver: (SpaceID) -> BrowserWindowID? = { _ in nil }
    @ObservationIgnored private var hostWindowsBySpace: [SpaceID: BrowserWindowID] = [:]
    @ObservationIgnored private var pendingInstallOpens: [BrowserExtensionServiceClientID: () -> Void] = [:]

    func hostWindow(for spaceID: SpaceID) -> BrowserWindowID? {
        hostWindowResolver(spaceID) ?? hostWindowsBySpace[spaceID]
    }

    init(behaviorPersistence: any BrowserExtensionSidebarBehaviorPersisting) {
        self.behaviorPersistence = behaviorPersistence
    }

    func register(
        client: BrowserExtensionServiceClientID, spaceID: SpaceID,
        defaults: BrowserExtensionSidebarDefaults, displayName: String, baseURL: URL
    ) {
        let registration = Registration(
            spaceID: spaceID, baseURL: baseURL,
            registry: .init(defaults: defaults, displayName: displayName),
            behavior: behaviorPersistence.load(for: client)
        )
        guard registrations[client] != registration else { return }
        registrations[client] = registration
        optionsRevision &+= 1
        refreshPresentations()
    }

    func unregister(client: BrowserExtensionServiceClientID) {
        guard registrations[client] != nil else { return }
        pendingInstallOpens[client] = nil
        for (window, spaces) in presentationsByWindow {
            for (space, presentations) in spaces {
                presentationsByWindow[window]?[space] = presentations.filter { $0.value.clientID != client }
                refresh(in: window, spaceID: space)
            }
        }
        refreshPresentations()
        registrations[client] = nil
        optionsRevision &+= 1
        eventHub.remove(client: client)
    }

    func requestOpenAtInstall(for client: BrowserExtensionServiceClientID, didOpen: @escaping () -> Void) {
        guard let registration = registrations[client], registration.registry.defaults.flavor == .sidebarAction,
            registration.registry.defaults.opensAtInstall
        else { return }
        pendingInstallOpens[client] = didOpen
        consumeInstallOpen(for: client)
    }

    private func consumeInstallOpen(for client: BrowserExtensionServiceClientID) {
        guard let completion = pendingInstallOpens[client], let registration = registrations[client],
            let window = hostWindow(for: registration.spaceID),
            let visible = visibility[window]?[registration.spaceID], visible.isAvailable
        else { return }
        do {
            try open(for: client, in: window, tab: visible.tabID)
            pendingInstallOpens[client] = nil
            completion()
        } catch {
            // A disabled first-install panel waits for applicable options.
        }
    }

    func setOptions(
        _ options: BrowserExtensionSidebarOptions, scope: BrowserExtensionSidebarScope,
        from client: BrowserExtensionServiceClientID
    ) throws {
        let registration = try registration(for: client)
        if let path = options.path, !path.isEmpty,
            BrowserExtensionSidebarResourcePolicy.documentURL(path: path, baseURL: registration.baseURL) == nil
        {
            throw BrowserExtensionSidebarError.invalidResource(path)
        }
        if case .packagePath(let path) = options.icon,
            BrowserExtensionSidebarResourcePolicy.documentURL(path: path, baseURL: registration.baseURL) == nil
        {
            throw BrowserExtensionSidebarError.invalidResource(path)
        }
        try update(client) { $0.registry.merge(options, at: scope) }
    }

    func clearTitle(scope: BrowserExtensionSidebarScope, from client: BrowserExtensionServiceClientID) throws {
        try update(client) { $0.registry.clearTitle(at: scope) }
    }

    func setChromeOptions(
        _ options: BrowserExtensionSidebarOptions, tab: TabID?, from client: BrowserExtensionServiceClientID
    ) throws {
        let registration = try registration(for: client)
        if let path = options.path, !path.isEmpty,
            BrowserExtensionSidebarResourcePolicy.documentURL(path: path, baseURL: registration.baseURL) == nil
        {
            throw BrowserExtensionSidebarError.invalidResource(path)
        }
        try update(client) { $0.registry.mergeChrome(options, for: tab) }
    }

    func clearIcon(scope: BrowserExtensionSidebarScope, from client: BrowserExtensionServiceClientID) throws {
        try update(client) { $0.registry.clearIcon(at: scope) }
    }

    func layer(_ scope: BrowserExtensionSidebarScope, for client: BrowserExtensionServiceClientID) throws
        -> BrowserExtensionSidebarOptions
    {
        try registration(for: client).registry.layer(scope)
    }

    func resolvedOptions(for tab: TabID?, client: BrowserExtensionServiceClientID) throws
        -> BrowserExtensionSidebarResolvedOptions
    {
        try registration(for: client).registry.resolved(for: tab)
    }

    func resolvedOptions(at scope: BrowserExtensionSidebarScope, client: BrowserExtensionServiceClientID) throws
        -> BrowserExtensionSidebarResolvedOptions
    {
        try registration(for: client).registry.resolved(at: scope)
    }

    func resolvedOptions(
        at scope: BrowserExtensionSidebarScope, client: BrowserExtensionServiceClientID, windowID: BrowserWindowID?
    ) throws
        -> BrowserExtensionSidebarResolvedOptions
    {
        try registration(for: client).registry.resolved(at: scope, in: windowID)
    }

    func setBehavior(_ behavior: BrowserExtensionSidebarBehavior, from client: BrowserExtensionServiceClientID) throws {
        try update(client) { $0.behavior = behavior }
        behaviorPersistence.save(behavior, for: client)
    }

    func behavior(for client: BrowserExtensionServiceClientID) throws -> BrowserExtensionSidebarBehavior {
        try registration(for: client).behavior
    }

    func flavor(for client: BrowserExtensionServiceClientID) -> BrowserExtensionSidebarFlavor? {
        _ = optionsRevision
        return registrations[client]?.registry.defaults.flavor
    }

    func baseURL(for client: BrowserExtensionServiceClientID) -> URL? { registrations[client]?.baseURL }

    func open(for client: BrowserExtensionServiceClientID, in window: BrowserWindowID, tab: TabID?) throws {
        let registration = try registration(for: client)
        let options = registration.registry.resolved(for: tab, in: window)
        guard options.presentsPanel,
            BrowserExtensionSidebarResourcePolicy.documentURL(path: options.path, baseURL: registration.baseURL) != nil
        else { throw BrowserExtensionSidebarError.noActivePanel }
        let scope = presentationScope(options, registration: registration)
        presentationsByWindow[window, default: [:]][registration.spaceID, default: [:]][scope] = .init(
            clientID: client, options: options)
        if scope == .default, let tab {
            // Opening a global panel for a tab replaces that tab's local
            // selection; a window-only open leaves other tab panels intact.
            presentationsByWindow[window]?[registration.spaceID]?[.tab(tab)] = nil
        }
        if visibility[window]?[registration.spaceID] == nil {
            visibility[window, default: [:]][registration.spaceID] = .init(tabID: tab, isAvailable: true)
        }
        refresh(in: window, spaceID: registration.spaceID)
    }

    func close(for client: BrowserExtensionServiceClientID, in window: BrowserWindowID, tab: TabID?) throws {
        let registration = try registration(for: client)
        if registration.registry.defaults.flavor == .sidePanel {
            try closeChromePanel(for: client, in: window, tab: tab)
        } else {
            removePresentation(for: client, in: window, spaceID: registration.spaceID, scope: .default)
        }
    }

    func closeChromePanel(for client: BrowserExtensionServiceClientID, in window: BrowserWindowID, tab: TabID?) throws {
        let registration = try registration(for: client)
        let scope = tab.map(BrowserExtensionSidebarScope.tab) ?? .default
        let options = registration.registry.resolved(at: scope)
        if tab != nil {
            guard options.scope == scope, options.presentsPanel else {
                throw BrowserExtensionSidebarError.noTabSpecificPanel
            }
        } else if !options.presentsPanel {
            throw BrowserExtensionSidebarError.noActivePanel
        }
        // Chrome validates the configured scope, even if its document is
        // already closed. Closing it again is then a successful no-op.
        removePresentation(for: client, in: window, spaceID: registration.spaceID, scope: scope)
    }

    private func removePresentation(
        for client: BrowserExtensionServiceClientID, in window: BrowserWindowID,
        spaceID: SpaceID, scope: BrowserExtensionSidebarScope
    ) {
        guard presentationsByWindow[window]?[spaceID]?[scope]?.clientID == client else { return }
        presentationsByWindow[window]?[spaceID]?[scope] = nil
        refresh(in: window, spaceID: spaceID)
    }

    func closePresentedPanel(in window: BrowserWindowID, spaceID: SpaceID, activeTab: TabID?) {
        // Chrome's UI close resets the global and active tab registries.
        // Inactive tabs retain their own panels and can restore them later.
        presentationsByWindow[window]?[spaceID]?[.default] = nil
        if let activeTab { presentationsByWindow[window]?[spaceID]?[.tab(activeTab)] = nil }
        refresh(in: window, spaceID: spaceID)
    }

    func toggle(for client: BrowserExtensionServiceClientID, in window: BrowserWindowID, tab: TabID?) throws {
        let registration = try registration(for: client)
        if let panel = panel(in: window, spaceID: registration.spaceID, activeTab: tab), panel.clientID == client {
            closePresentedPanel(in: window, spaceID: registration.spaceID, activeTab: tab)
        } else {
            try open(for: client, in: window, tab: tab)
        }
    }

    func isOpen(for client: BrowserExtensionServiceClientID, in window: BrowserWindowID) -> Bool {
        _ = optionsRevision
        guard let space = registrations[client]?.spaceID else { return false }
        let panel = panel(in: window, spaceID: space, activeTab: visibility[window]?[space]?.tabID)
        return panel?.clientID == client && panel?.documentURL != nil
    }

    func panel(in window: BrowserWindowID, spaceID: SpaceID, activeTab: TabID?) -> BrowserExtensionSidebarPanel? {
        _ = optionsRevision
        guard let presentations = presentationsByWindow[window]?[spaceID],
            let intent = activeTab.flatMap({ presentations[.tab($0)] }) ?? presentations[.default],
            let registration = registrations[intent.clientID],
            registration.registry.resolved(for: activeTab, in: window).presentsPanel
        else { return nil }
        return makePanel(
            client: intent.clientID, options: presentationOptions(intent, activeTab: activeTab, window: window),
            isAvailable: visibility[window]?[spaceID]?.isAvailable ?? true)
    }

    /// Hidden tab and Space documents retain their conversation. Only closing,
    /// replacing, disabling or removing their owning scope releases them.
    func retainedPanels(in window: BrowserWindowID, spaceID: SpaceID) -> [BrowserExtensionSidebarPanel] {
        (presentationsByWindow[window]?[spaceID] ?? [:]).values.compactMap {
            makePanel(
                client: $0.clientID,
                options: presentationOptions($0, activeTab: visibility[window]?[spaceID]?.tabID, window: window),
                isAvailable: true)
        }
    }

    private func presentationOptions(
        _ intent: BrowserExtensionSidebarPresentation, activeTab: TabID?, window: BrowserWindowID
    )
        -> BrowserExtensionSidebarResolvedOptions
    {
        guard let registration = registrations[intent.clientID],
            registration.registry.defaults.flavor == .sidebarAction
        else { return intent.options }
        // Firefox keeps one window sidebar and resolves its resource from
        // the selected tab. Chrome retains each explicitly opened scope.
        return registration.registry.resolved(for: activeTab, in: window)
    }

    func availablePanels(in window: BrowserWindowID, spaceID: SpaceID, activeTab: TabID?)
        -> [BrowserExtensionSidebarPanel]
    {
        _ = optionsRevision
        guard visibility[window]?[spaceID]?.isAvailable != false else { return [] }
        return registrations.filter { $0.value.spaceID == spaceID }.keys.compactMap {
            makePanel(client: $0, activeTab: activeTab, window: window, isAvailable: true)
        }.filter { $0.documentURL != nil }.sorted {
            if $0.title == $1.title { return $0.clientID < $1.clientID }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    func reconcilePresentation(in window: BrowserWindowID, spaceID: SpaceID, activeTab: TabID?, isAvailable: Bool) {
        if isAvailable {
            hostWindowsBySpace[spaceID] = window
        } else if hostWindowsBySpace[spaceID] == window {
            hostWindowsBySpace[spaceID] = nil
        }
        let previous = visibility[window]?[spaceID]
        let next = Visibility(
            tabID: isAvailable ? activeTab : activeTab ?? previous?.tabID, isAvailable: isAvailable)
        if previous != next {
            visibility[window, default: [:]][spaceID] = next
            // Tab selection is an explicit input to panel resolution.
            // Availability also invalidates options for observers without a tab input.
            if previous?.isAvailable != next.isAvailable,
                registrations.values.contains(where: { $0.spaceID == spaceID })
            {
                optionsRevision &+= 1
            }
            refresh(in: window, spaceID: spaceID)
        }
        for client in Array(pendingInstallOpens.keys) where registrations[client]?.spaceID == spaceID {
            consumeInstallOpen(for: client)
        }
    }

    func release(window: BrowserWindowID) {
        for client in Array(registrations.keys) { registrations[client]?.registry.release(windowID: window) }
        hostWindowsBySpace = hostWindowsBySpace.filter { $0.value != window }
        let spaces = Array(visiblePanels[window]?.keys ?? [:].keys)
        presentationsByWindow[window] = nil
        for space in spaces { refresh(in: window, spaceID: space) }
        visibility[window] = nil
        visiblePanels[window] = nil
        optionsRevision &+= 1
    }

    func events(for client: BrowserExtensionServiceClientID) -> AsyncStream<BrowserExtensionSidebarEvent> {
        eventHub.events(for: client)
    }

    func repair(using session: BrowserSession) {
        let previousRegistrations = registrations
        let previousVisibility = visibility
        let previousPresentations = presentationsByWindow
        for (client, registration) in registrations {
            guard let space = session.space(id: registration.spaceID) else {
                unregister(client: client)
                continue
            }
            registrations[client]?.registry.repair(liveTabs: Set(space.tabs.map(\.id)))
            for (window, spaces) in presentationsByWindow {
                guard let presentations = spaces[space.id] else { continue }
                presentationsByWindow[window]?[space.id] = presentations.filter { scope, _ in
                    if case .tab(let tab) = scope { return space.contains(tab) }
                    return true
                }
            }
            for (window, spaces) in visibility {
                guard let current = spaces[space.id], let tab = current.tabID, !space.contains(tab) else { continue }
                visibility[window]?[space.id]?.tabID = space.selectedTabID
            }
        }
        guard
            registrations != previousRegistrations || visibility != previousVisibility
                || presentationsByWindow != previousPresentations
        else { return }
        optionsRevision &+= 1
        refreshPresentations()
    }

    private func registration(for client: BrowserExtensionServiceClientID) throws -> Registration {
        _ = optionsRevision
        guard let registration = registrations[client] else { throw BrowserExtensionSidebarError.unavailable }
        return registration
    }

    private func update(_ client: BrowserExtensionServiceClientID, mutation: (inout Registration) -> Void) throws {
        let previous = try registration(for: client)
        var value = previous
        mutation(&value)
        guard registrations[client] != value else { return }
        registrations[client] = value
        // Update only each open document's own options. Disabling a scope
        // also removes its open intent so it cannot reappear with stale state.
        for (window, spaces) in presentationsByWindow where value.registry.defaults.flavor == .sidePanel {
            for (scope, intent) in spaces[value.spaceID] ?? [:] where intent.clientID == client {
                let options = value.registry.resolved(at: intent.options.scope)
                if !options.presentsPanel {
                    presentationsByWindow[window]?[value.spaceID]?[scope] = nil
                } else if previous.registry.resolved(at: intent.options.scope) != options {
                    presentationsByWindow[window]?[value.spaceID]?[scope] = .init(clientID: client, options: options)
                }
            }
        }
        optionsRevision &+= 1
        refreshPresentations()
        consumeInstallOpen(for: client)
    }

    private func makePanel(
        client: BrowserExtensionServiceClientID, activeTab: TabID?, window: BrowserWindowID, isAvailable: Bool
    )
        -> BrowserExtensionSidebarPanel?
    {
        guard let registration = registrations[client] else { return nil }
        let options = registration.registry.resolved(for: activeTab, in: window)
        guard options.presentsPanel else { return nil }
        return makePanel(client: client, options: options, isAvailable: isAvailable)
    }

    private func makePanel(
        client: BrowserExtensionServiceClientID, options: BrowserExtensionSidebarResolvedOptions, isAvailable: Bool
    ) -> BrowserExtensionSidebarPanel? {
        guard let registration = registrations[client] else { return nil }
        let url =
            isAvailable
            ? BrowserExtensionSidebarResourcePolicy.documentURL(path: options.path, baseURL: registration.baseURL) : nil
        let tabID: TabID?
        if case .tab(let tab) = presentationScope(options, registration: registration) {
            tabID = tab
        } else {
            tabID = nil
        }
        return .init(
            clientID: client, spaceID: registration.spaceID, documentURL: url,
            path: options.path, title: options.title, icon: options.icon, tabID: tabID)
    }

    private func presentationScope(
        _ options: BrowserExtensionSidebarResolvedOptions, registration: Registration
    ) -> BrowserExtensionSidebarScope {
        if registration.registry.defaults.flavor == .sidePanel, case .tab = options.scope { return options.scope }
        return .default
    }

    private func refreshPresentations() {
        let windows = Set(presentationsByWindow.keys).union(visiblePanels.keys)
        for window in windows {
            let spaces = Set(presentationsByWindow[window]?.keys ?? [:].keys)
                .union(visiblePanels[window]?.keys ?? [:].keys)
            for space in spaces { refresh(in: window, spaceID: space) }
        }
    }

    private func refresh(in window: BrowserWindowID, spaceID: SpaceID) {
        let previous = visiblePanels[window]?[spaceID]
        let candidate = panel(in: window, spaceID: spaceID, activeTab: visibility[window]?[spaceID]?.tabID)
        let next = candidate?.documentURL == nil ? nil : candidate
        visiblePanels[window, default: [:]][spaceID] = next
        guard
            previous?.documentURL != next?.documentURL || previous?.tabID != next?.tabID
                || previous?.clientID != next?.clientID
        else { return }
        if let previous { publish(.closed, panel: previous, window: window) }
        if let next { publish(.opened, panel: next, window: window) }
    }

    private func publish(
        _ kind: BrowserExtensionSidebarEvent.Kind, panel: BrowserExtensionSidebarPanel, window: BrowserWindowID
    ) {
        eventHub.publish(
            .init(
                kind: kind, windowID: window, spaceID: panel.spaceID,
                tabID: panel.tabID, path: panel.path), to: panel.clientID)
    }
}
