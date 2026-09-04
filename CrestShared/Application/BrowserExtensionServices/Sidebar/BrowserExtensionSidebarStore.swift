import Foundation
import Observation

/// Open intent survives a temporarily inapplicable tab or a locked Space.
/// Visible documents do not. The host reconciles its actual selection here;
/// consumers receive close/open events when that document identity changes.
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

    private(set) var presentationsByWindow: [BrowserWindowID: [SpaceID: BrowserExtensionSidebarPresentation]] = [:]
    private var contextualPresentations: [BrowserWindowID: [SpaceID: [TabID: BrowserExtensionSidebarPresentation]]] =
        [:]
    private var closedTabs: [BrowserWindowID: [SpaceID: Set<TabID>]] = [:]
    private(set) var optionsRevision = 0
    @ObservationIgnored private var registrations: [BrowserExtensionServiceClientID: Registration] = [:]
    @ObservationIgnored private var visibility: [BrowserWindowID: [SpaceID: Visibility]] = [:]
    @ObservationIgnored private var visiblePanels: [BrowserWindowID: [SpaceID: BrowserExtensionSidebarPanel]] = [:]
    @ObservationIgnored private let behaviorPersistence: any BrowserExtensionSidebarBehaviorPersisting
    @ObservationIgnored private let eventHub = BrowserExtensionSidebarEventHub()
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
            for (space, presentation) in spaces where presentation.clientID == client {
                presentationsByWindow[window]?[space] = nil
                refresh(in: window, spaceID: space)
            }
        }
        for (window, spaces) in contextualPresentations {
            for (space, tabs) in spaces {
                contextualPresentations[window]?[space] = tabs.filter { $0.value.clientID != client }
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
        } catch { /* A disabled first-install panel waits for applicable options. */  }
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
        let options = registration.registry.resolved(for: tab)
        guard options.presentsPanel,
            BrowserExtensionSidebarResourcePolicy.documentURL(path: options.path, baseURL: registration.baseURL) != nil
        else { throw BrowserExtensionSidebarError.noActivePanel }
        let tabID: TabID? = if case .tab(let id) = options.scope { id } else { nil }
        let presentation = BrowserExtensionSidebarPresentation(
            clientID: client, tabID: tabID, path: options.path
        )
        if let tabID, registration.registry.defaults.flavor == .sidePanel {
            contextualPresentations[window, default: [:]][registration.spaceID, default: [:]][tabID] = presentation
        } else {
            if let tab { contextualPresentations[window]?[registration.spaceID]?[tab] = nil }
            if registration.registry.defaults.flavor == .sidebarAction,
                let active = visibility[window]?[registration.spaceID]?.tabID
            {
                contextualPresentations[window]?[registration.spaceID]?[active] = nil
            }
            presentationsByWindow[window, default: [:]][registration.spaceID] = presentation
            closedTabs[window]?[registration.spaceID] = nil
        }
        if let tab = tab ?? visibility[window]?[registration.spaceID]?.tabID {
            closedTabs[window]?[registration.spaceID]?.remove(tab)
        }
        if visibility[window]?[registration.spaceID] == nil {
            visibility[window, default: [:]][registration.spaceID] = .init(tabID: tab, isAvailable: true)
        }
        refresh(in: window, spaceID: registration.spaceID)
    }

    func close(for client: BrowserExtensionServiceClientID, in window: BrowserWindowID, tab: TabID?) throws {
        let registration = try registration(for: client)
        if let tab, registration.registry.resolved(for: tab).scope != .tab(tab) {
            throw BrowserExtensionSidebarError.noTabSpecificPanel
        }
        guard isOpen(for: client, in: window) else { return }
        if let tab, visiblePanels[window]?[registration.spaceID]?.tabID != tab { return }
        presentationsByWindow[window]?[registration.spaceID] = nil
        contextualPresentations[window]?[registration.spaceID] = nil
        closedTabs[window]?[registration.spaceID] = nil
        refresh(in: window, spaceID: registration.spaceID)
    }

    func closeChromePanel(for client: BrowserExtensionServiceClientID, in window: BrowserWindowID, tab: TabID?) throws {
        let registration = try registration(for: client)
        let spaceID = registration.spaceID
        if let tab {
            let options = registration.registry.resolved(for: tab)
            guard options.scope == .tab(tab), options.presentsPanel else {
                throw BrowserExtensionSidebarError.noTabSpecificPanel
            }
            if contextualPresentations[window]?[spaceID]?[tab]?.clientID == client {
                contextualPresentations[window]?[spaceID]?[tab] = nil
            }
            if presentationsByWindow[window]?[spaceID]?.clientID == client {
                closedTabs[window, default: [:]][spaceID, default: []].insert(tab)
            }
        } else {
            guard registration.registry.resolved(at: .default).presentsPanel else {
                throw BrowserExtensionSidebarError.noActivePanel
            }
            // Closing a global entry leaves a visible contextual entry alone.
            if let current = visiblePanels[window]?[spaceID], current.clientID == client, let tab = current.tabID {
                contextualPresentations[window, default: [:]][spaceID, default: [:]][tab] = .init(
                    clientID: client, tabID: tab, path: current.path
                )
            }
            if presentationsByWindow[window]?[spaceID]?.clientID == client {
                presentationsByWindow[window]?[spaceID] = nil
            }
        }
        refresh(in: window, spaceID: spaceID)
    }

    func toggle(for client: BrowserExtensionServiceClientID, in window: BrowserWindowID, tab: TabID?) throws {
        if isOpen(for: client, in: window) {
            try close(for: client, in: window, tab: nil)
            return
        }
        let registration = try registration(for: client)
        if let active = visibility[window]?[registration.spaceID]?.tabID {
            contextualPresentations[window]?[registration.spaceID]?[active] = nil
        }
        try open(for: client, in: window, tab: tab)
    }

    func isOpen(for client: BrowserExtensionServiceClientID, in window: BrowserWindowID) -> Bool {
        _ = optionsRevision
        guard let space = registrations[client]?.spaceID else { return false }
        let panel = panel(in: window, spaceID: space, activeTab: visibility[window]?[space]?.tabID)
        return panel?.clientID == client && panel?.documentURL != nil
    }

    func panel(in window: BrowserWindowID, spaceID: SpaceID, activeTab: TabID?) -> BrowserExtensionSidebarPanel? {
        _ = optionsRevision
        if let activeTab, closedTabs[window]?[spaceID]?.contains(activeTab) == true { return nil }
        let contextual = activeTab.flatMap { contextualPresentations[window]?[spaceID]?[$0] }
        guard let intent = contextual ?? presentationsByWindow[window]?[spaceID] else { return nil }
        return makePanel(
            client: intent.clientID, activeTab: activeTab,
            isAvailable: visibility[window]?[spaceID]?.isAvailable ?? true)
    }

    func availablePanels(in window: BrowserWindowID, spaceID: SpaceID, activeTab: TabID?)
        -> [BrowserExtensionSidebarPanel]
    {
        _ = optionsRevision
        guard visibility[window]?[spaceID]?.isAvailable != false else { return [] }
        return registrations.filter { $0.value.spaceID == spaceID }.keys.compactMap {
            makePanel(client: $0, activeTab: activeTab, isAvailable: true)
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
        let next = Visibility(tabID: activeTab, isAvailable: isAvailable)
        if visibility[window]?[spaceID] != next {
            visibility[window, default: [:]][spaceID] = next
            optionsRevision &+= 1
            refresh(in: window, spaceID: spaceID)
        }
        for client in Array(pendingInstallOpens.keys) where registrations[client]?.spaceID == spaceID {
            consumeInstallOpen(for: client)
        }
    }

    func release(window: BrowserWindowID) {
        hostWindowsBySpace = hostWindowsBySpace.filter { $0.value != window }
        let spaces = Array(visiblePanels[window]?.keys ?? [:].keys)
        presentationsByWindow[window] = nil
        contextualPresentations[window] = nil
        closedTabs[window] = nil
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
        let previousContextual = contextualPresentations
        let previousClosedTabs = closedTabs
        for (client, registration) in registrations {
            guard let space = session.space(id: registration.spaceID) else {
                unregister(client: client)
                continue
            }
            registrations[client]?.registry.repair(liveTabs: Set(space.tabs.map(\.id)))
            for window in contextualPresentations.keys {
                contextualPresentations[window]?[space.id] = contextualPresentations[window]?[space.id]?.filter {
                    space.contains($0.key)
                }
                closedTabs[window]?[space.id] = closedTabs[window]?[space.id]?.filter { space.contains($0) }
            }
            for (window, spaces) in visibility {
                guard let current = spaces[space.id], let tab = current.tabID, !space.contains(tab) else { continue }
                visibility[window]?[space.id]?.tabID = space.selectedTabID
            }
        }
        guard
            registrations != previousRegistrations || visibility != previousVisibility
                || contextualPresentations != previousContextual || closedTabs != previousClosedTabs
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
        var value = try registration(for: client)
        mutation(&value)
        guard registrations[client] != value else { return }
        registrations[client] = value
        optionsRevision &+= 1
        refreshPresentations()
        consumeInstallOpen(for: client)
    }

    private func makePanel(client: BrowserExtensionServiceClientID, activeTab: TabID?, isAvailable: Bool)
        -> BrowserExtensionSidebarPanel?
    {
        guard let registration = registrations[client] else { return nil }
        let options = registration.registry.resolved(for: activeTab)
        let url =
            options.presentsPanel && isAvailable
            ? BrowserExtensionSidebarResourcePolicy.documentURL(path: options.path, baseURL: registration.baseURL) : nil
        let tabID: TabID? = if case .tab(let id) = options.scope { id } else { nil }
        return .init(
            clientID: client, spaceID: registration.spaceID, documentURL: url,
            path: options.path, title: options.title, icon: options.icon, tabID: tabID)
    }

    private func refreshPresentations() {
        let windows = Set(presentationsByWindow.keys).union(contextualPresentations.keys).union(visiblePanels.keys)
        for window in windows {
            let spaces = Set(presentationsByWindow[window]?.keys ?? [:].keys)
                .union(contextualPresentations[window]?.keys ?? [:].keys).union(visiblePanels[window]?.keys ?? [:].keys)
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
