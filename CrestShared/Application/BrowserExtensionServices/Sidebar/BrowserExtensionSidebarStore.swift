import Foundation
import Observation

/// One selected extension document per window and Space. Tab options choose
/// the resource when opening; tab selection never replaces or closes it.
/// Extensions receive native tab events to follow the active page themselves.
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
        presentationsByWindow[window, default: [:]][registration.spaceID] = .init(
            clientID: client, options: options)
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
        guard presentationsByWindow[window]?[registration.spaceID]?.clientID == client else { return }
        closePresentedPanel(in: window, spaceID: registration.spaceID)
    }

    func closeChromePanel(for client: BrowserExtensionServiceClientID, in window: BrowserWindowID, tab: TabID?) throws {
        let registration = try registration(for: client)
        if let tab {
            let options = registration.registry.resolved(for: tab)
            guard options.scope == .tab(tab), options.presentsPanel else {
                throw BrowserExtensionSidebarError.noTabSpecificPanel
            }
        } else if !registration.registry.resolved(at: .default).presentsPanel {
            throw BrowserExtensionSidebarError.noActivePanel
        }
        // Chrome's target still validates the caller's configured resource.
        // Crest has one selected panel, so there is no hidden tab selection
        // to restore after closing it.
        guard presentationsByWindow[window]?[registration.spaceID]?.clientID == client else { return }
        closePresentedPanel(in: window, spaceID: registration.spaceID)
    }

    func closePresentedPanel(in window: BrowserWindowID, spaceID: SpaceID) {
        presentationsByWindow[window]?[spaceID] = nil
        refresh(in: window, spaceID: spaceID)
    }

    func toggle(for client: BrowserExtensionServiceClientID, in window: BrowserWindowID, tab: TabID?) throws {
        let registration = try registration(for: client)
        if presentationsByWindow[window]?[registration.spaceID]?.clientID == client {
            closePresentedPanel(in: window, spaceID: registration.spaceID)
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
        guard let intent = presentationsByWindow[window]?[spaceID] else { return nil }
        return makePanel(
            client: intent.clientID, options: intent.options,
            isAvailable: visibility[window]?[spaceID]?.isAvailable ?? true)
    }

    /// Keep the selected document alive when another Space is visible. A
    /// replaced or closed panel is absent and is released by the page pool.
    func retainedPanels(in window: BrowserWindowID, spaceID: SpaceID) -> [BrowserExtensionSidebarPanel] {
        guard let intent = presentationsByWindow[window]?[spaceID],
            let panel = makePanel(client: intent.clientID, options: intent.options, isAvailable: true)
        else { return [] }
        return [panel]
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
        for (client, registration) in registrations {
            guard let space = session.space(id: registration.spaceID) else {
                unregister(client: client)
                continue
            }
            registrations[client]?.registry.repair(liveTabs: Set(space.tabs.map(\.id)))
            for (window, spaces) in visibility {
                guard let current = spaces[space.id], let tab = current.tabID, !space.contains(tab) else { continue }
                visibility[window]?[space.id]?.tabID = space.selectedTabID
            }
        }
        guard
            registrations != previousRegistrations || visibility != previousVisibility
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
        // Apply explicit option changes to the resource that was opened. An
        // unrelated tab's options, disabled tabs and tab selection do not
        // destroy an already open conversation. Disabling controls new opens.
        for (window, spaces) in presentationsByWindow {
            guard let intent = spaces[value.spaceID], intent.clientID == client else { continue }
            let scope = intent.options.scope
            let options = value.registry.resolved(at: scope)
            if previous.registry.resolved(at: scope) != options, options.presentsPanel {
                presentationsByWindow[window]?[value.spaceID] = .init(clientID: client, options: options)
            }
        }
        optionsRevision &+= 1
        refreshPresentations()
        consumeInstallOpen(for: client)
    }

    private func makePanel(client: BrowserExtensionServiceClientID, activeTab: TabID?, isAvailable: Bool)
        -> BrowserExtensionSidebarPanel?
    {
        guard let registration = registrations[client] else { return nil }
        let options = registration.registry.resolved(for: activeTab)
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
        return .init(
            clientID: client, spaceID: registration.spaceID, documentURL: url,
            path: options.path, title: options.title, icon: options.icon, tabID: nil)
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
