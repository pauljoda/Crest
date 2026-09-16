import Foundation
import WebKit

extension BrowserExtensionTabWindowCoordinator {
    func registerWindow(
        id: BrowserWindowID, browser: any BrowserExtensionTabWindowSessionHandling,
        pageProvider: any BrowserExtensionPageProviding, focus: @escaping () -> Void, close: @escaping () -> Void
    ) {
        hasRegisteredHostWindows = true
        if self.browser == nil, (browser as? BrowserStore)?.isTemporaryWorkspace != true { self.browser = browser }
        if hostWindows[id] == nil { hostWindowOrder.append(id) }
        hostWindows[id] = .init(id: id, browser: browser, pageProvider: pageProvider, focus: focus, close: close)
        (tabGroupService as? BrowserExtensionTabGroupRoutingService)?.refreshSources()
        for spaceID in controllers.keys { registerHostAdapters(in: spaceID) }
        reconcile(session: browser.session)
    }

    func unregisterWindow(id: BrowserWindowID) {
        guard hostWindows.removeValue(forKey: id) != nil else { return }
        hostWindowOrder.removeAll { $0 == id }
        if focusedHostWindowID == id { focusedHostWindowID = nil }
        let previousOwners = tabOwnerWindowIDs.filter { $0.value == id }.map(\.key)
        for tabID in previousOwners { tabOwnerWindowIDs[tabID] = nil }
        reconcileTabOwners()
        var closed: [(WKWebExtensionController, BrowserExtensionWindowAdapter)] = []
        for spaceID in Array(windowsBySpace.keys) {
            guard let oldWindow = windowsBySpace[spaceID]?.removeValue(forKey: id),
                let entry = controllers[spaceID]
            else { continue }
            lastSelectedTabsByWindow[ObjectIdentifier(oldWindow)] = nil
            let replacementHost = hostWindowOrder.compactMap { hostWindows[$0] }.first {
                sharesPrimaryWorkspace($0) && $0.browser?.session.space(id: spaceID) != nil
            }
            if entry.window === oldWindow, browser?.session.space(id: spaceID) != nil,
                replacementHost == nil
            {
                // A remaining temporary host cannot become the persisted
                // workspace's window. Keep its normal tabs explicitly unhosted.
                oldWindow.hostWindowID = nil
            } else if let replacement = (replacementHost ?? preferredHost(in: spaceID)).flatMap({
                windowsBySpace[spaceID]?[$0.id]
            }) {
                if entry.window === oldWindow {
                    controllers[spaceID] = .init(controller: entry.controller, window: replacement)
                }
                closed.append((entry.controller, oldWindow))
            } else {
                closed.append((entry.controller, oldWindow))
            }
        }
        if hostWindows.isEmpty { setHostWindowFocused(false) }
        reconcileCurrentSession()
        for (controller, window) in closed { controller.didCloseWindow(window) }
        (tabGroupService as? BrowserExtensionTabGroupRoutingService)?.refreshSources()
    }

    func setHostWindowFocused(_ isFocused: Bool, windowID: BrowserWindowID) {
        if isFocused {
            guard hostWindows[windowID] != nil else { return }
            focusedHostWindowID = windowID
        } else if focusedHostWindowID == windowID {
            focusedHostWindowID = nil
        }
        reconcileWindowFocus()
    }

    func setExtensionTabOwner(_ tabID: TabID, in spaceID: SpaceID, windowID: BrowserWindowID) {
        tabOwnerWindowIDs[tabID] = windowID
        guard hostWindows[windowID]?.browser?.session.space(id: spaceID)?.contains(tabID) == true else { return }
        registerHostAdapters(in: spaceID)
        reconcileCurrentSession()
    }

    func registerHostAdapters(in spaceID: SpaceID) {
        guard let entry = controllers[spaceID] else { return }
        for id in hostWindowOrder {
            guard hostWindows[id]?.browser?.session.space(id: spaceID) != nil,
                windowsBySpace[spaceID]?[id] == nil
            else { continue }
            if entry.window.hostWindowID == id
                || (entry.window.hostWindowID == nil && hostWindows[id].map(sharesPrimaryWorkspace) == true)
            {
                entry.window.hostWindowID = id
                windowsBySpace[spaceID, default: [:]][id] = entry.window
                continue
            }
            let window = BrowserExtensionWindowAdapter(spaceID: spaceID, hostWindowID: id, coordinator: self)
            windowsBySpace[spaceID, default: [:]][id] = window
            entry.controller.didOpenWindow(window)
        }
    }

    func preferredHost(in spaceID: SpaceID) -> BrowserExtensionHostWindow? {
        if let id = focusedHostWindowID, let host = hostWindows[id], host.browser?.session.space(id: spaceID) != nil {
            return host
        }
        return hostWindowOrder.compactMap { hostWindows[$0] }.first { $0.browser?.session.space(id: spaceID) != nil }
    }

    private func sharesPrimaryWorkspace(_ host: BrowserExtensionHostWindow) -> Bool {
        if let primary = browser as? BrowserStore, let candidate = host.browser as? BrowserStore {
            return primary.family === candidate.family
        }
        return host.browser === browser
    }

    func ownerHost(for tabID: TabID, in spaceID: SpaceID) -> BrowserExtensionHostWindow? {
        if let id = tabOwnerWindowIDs[tabID], let host = hostWindows[id],
            host.browser?.session.space(id: spaceID)?.contains(tabID) == true
                || transientTabsBySpace[spaceID]?.contains(where: { $0.id == tabID }) == true
        {
            return host
        }
        return hostWindowOrder.compactMap { hostWindows[$0] }.first {
            $0.browser?.session.space(id: spaceID)?.contains(tabID) == true
        }
    }

    func browser(for tabID: TabID, in spaceID: SpaceID) -> (any BrowserExtensionTabWindowSessionHandling)? {
        if let host = ownerHost(for: tabID, in: spaceID) { return host.browser }
        guard
            browser?.session.space(id: spaceID)?.contains(tabID) == true
                || transientTabsBySpace[spaceID]?.contains(where: { $0.id == tabID }) == true
        else { return nil }
        return browser
    }

    func pageProvider(for tabID: TabID, in spaceID: SpaceID) -> (any BrowserExtensionPageProviding)? {
        ownerHost(for: tabID, in: spaceID)?.pageProvider ?? pageProvider
    }

    func pageProviders(in spaceID: SpaceID) -> [any BrowserExtensionPageProviding] {
        var result: [any BrowserExtensionPageProviding] = []
        var seen: Set<ObjectIdentifier> = []
        for provider in [pageProvider] + hostWindowOrder.map({ hostWindows[$0]?.pageProvider }) {
            guard let provider, seen.insert(ObjectIdentifier(provider)).inserted else { continue }
            result.append(provider)
        }
        return result
    }

    func host(for window: BrowserExtensionWindowAdapter?) -> BrowserExtensionHostWindow? {
        window?.hostWindowID.flatMap { hostWindows[$0] }
    }

    func reconcileTabOwners() {
        for sources in hostTabProjection().sources.values {
            for (tabID, source) in sources {
                tabOwnerWindowIDs[tabID] = source.host?.id
            }
        }
    }

    /// A full projection reads each host session once and assigns each window's
    /// tab indices once. Single-tab getters keep their live lookup path.
    func projectedHostState(
        for session: BrowserSession
    ) -> (state: BrowserExtensionSessionState, windowsByTabID: [TabID: BrowserExtensionWindowAdapter]) {
        let primary = browser?.session
        let projection = hostTabProjection(including: primary)
        var windowsByTabID: [TabID: BrowserExtensionWindowAdapter] = [:]
        var windows: [ObjectIdentifier: BrowserExtensionWindowAdapter] = [:]
        for (spaceID, sources) in projection.sources {
            for (tabID, source) in sources {
                let window =
                    auxiliaryWindowByTabID[tabID]
                    ?? source.host.flatMap { windowsBySpace[spaceID]?[$0.id] }
                    ?? controllers[spaceID]?.window
                if let window {
                    windowsByTabID[tabID] = window
                    windows[ObjectIdentifier(window)] = window
                }
            }
        }
        var indicesByTabID: [TabID: Int] = [:]
        for window in windows.values {
            let ownerSession = window.hostWindowID.flatMap { projection.sessions[$0] } ?? primary
            let tabs = ownerSession?.space(id: window.spaceID)?.tabs ?? []
            var index = 0
            for tab in tabs where windowsByTabID[tab.id] === window {
                indicesByTabID[tab.id] = index
                index += 1
            }
        }
        let state = BrowserExtensionSessionState(
            selectedSpaceID: session.selectedSpaceID,
            spaces: session.spaces.map { space in
                BrowserExtensionSpaceState(
                    id: space.id,
                    tabs: space.tabs.compactMap { tab in
                        guard let source = projection.sources[space.id]?[tab.id] else { return nil }
                        let provider = source.host?.pageProvider ?? pageProvider
                        let activity = BrowserExtensionTabRuntimeActivity(
                            isLoadingComplete: provider?.extensionWebView(for: tab.id, in: space.id)?.isLoading != true,
                            isReaderModeActive: provider?.extensionReaderModeState(for: tab.id, in: space.id).isActive
                                == true
                        )
                        return BrowserExtensionTabState(
                            tab: source.tab, index: indicesByTabID[tab.id] ?? source.index,
                            isSelected: source.isSelected, runtimeActivity: activity)
                    })
            })
        return (state, windowsByTabID)
    }

    private struct HostTabSource {
        let tab: BrowserTab
        let index: Int
        let isSelected: Bool
        let host: BrowserExtensionHostWindow?
    }

    private struct HostTabProjection {
        var sessions: [BrowserWindowID: BrowserSession] = [:]
        var sources: [SpaceID: [TabID: HostTabSource]] = [:]
    }

    private func hostTabProjection(including primary: BrowserSession? = nil) -> HostTabProjection {
        var projection = HostTabProjection()
        for space in primary?.spaces ?? [] {
            for (index, tab) in space.tabs.enumerated() {
                projection.sources[space.id, default: [:]][tab.id] = HostTabSource(
                    tab: tab, index: index, isSelected: tab.id == space.selectedTabID, host: nil)
            }
        }
        for id in hostWindowOrder {
            guard let host = hostWindows[id], let session = host.browser?.session else { continue }
            projection.sessions[id] = session
            for space in session.spaces {
                for (index, tab) in space.tabs.enumerated()
                where projection.sources[space.id]?[tab.id]?.host == nil || tabOwnerWindowIDs[tab.id] == id {
                    projection.sources[space.id, default: [:]][tab.id] = HostTabSource(
                        tab: tab, index: index, isSelected: tab.id == space.selectedTabID, host: host)
                }
            }
        }
        return projection
    }

    func combinedSession(fallback: BrowserSession) -> BrowserSession {
        var result = browser?.session ?? fallback
        for host in hostWindowOrder.compactMap({ hostWindows[$0] }) {
            guard let session = host.browser?.session else { continue }
            for space in session.spaces {
                guard let index = result.spaces.firstIndex(where: { $0.id == space.id }) else {
                    result.spaces.append(space)
                    continue
                }
                let existingTabs = Set(result.spaces[index].tabs.map(\.id))
                result.spaces[index].tabs.append(contentsOf: space.tabs.filter { !existingTabs.contains($0.id) })
                let existingFolders = Set(result.spaces[index].folders.map(\.id))
                result.spaces[index].folders.append(
                    contentsOf: space.folders.filter { !existingFolders.contains($0.id) })
            }
        }
        if let focused = focusedHostWindowID.flatMap({ hostWindows[$0]?.browser }) {
            result.selectedSpaceID = focused.session.selectedSpaceID
        }
        return result
    }

    func ownedTabIDs(in window: BrowserExtensionWindowAdapter?) -> [TabID] {
        guard let window else { return [] }
        let session = host(for: window)?.browser?.session ?? browser?.session
        let ids =
            session?.space(id: window.spaceID)?.tabs.map(\.id)
            ?? lastState?.space(window.spaceID)?.tabs.map(\.id) ?? []
        let transientIDs = transientTabsBySpace[window.spaceID]?.map(\.id) ?? []
        let transientMembership = Set(transientIDs)
        let hostMembership = hostWindows.mapValues { host in
            Set(host.browser?.session.space(id: window.spaceID)?.tabs.map(\.id) ?? [])
        }
        var firstOwnerByTabID: [TabID: BrowserWindowID] = [:]
        for hostID in hostWindowOrder {
            for tabID in hostMembership[hostID] ?? [] where firstOwnerByTabID[tabID] == nil {
                firstOwnerByTabID[tabID] = hostID
            }
        }
        return (ids + transientIDs).filter { tabID in
            var ownerID = firstOwnerByTabID[tabID]
            if let assigned = tabOwnerWindowIDs[tabID], hostWindows[assigned] != nil,
                hostMembership[assigned]?.contains(tabID) == true || transientMembership.contains(tabID)
            {
                ownerID = assigned
            }
            let resolved =
                auxiliaryWindowByTabID[tabID]
                ?? ownerID.flatMap { windowsBySpace[window.spaceID]?[$0] }
                ?? controllers[window.spaceID]?.window
            return resolved === window
        }
    }

    func reconcileHostSelections(in spaceID: SpaceID, controller: WKWebExtensionController) {
        for window in windowsBySpace[spaceID]?.values.map({ $0 }) ?? [] {
            let key = ObjectIdentifier(window)
            let selected = host(for: window)?.browser?.session.space(id: spaceID)?.selectedTabID
            let next = selected.flatMap { self.window(for: $0, in: spaceID) === window ? $0 : nil }
            let previous = lastSelectedTabsByWindow[key]
            guard next != previous else { continue }
            lastSelectedTabsByWindow[key] = next
            let previousAdapter = previous.flatMap { tabsBySpace[spaceID]?[$0] }
            if let previousAdapter { controller.didDeselectTabs([previousAdapter]) }
            if let next, let adapter = tabsBySpace[spaceID]?[next] {
                controller.didSelectTabs([adapter])
                controller.didActivateTab(adapter, previousActiveTab: previousAdapter)
            }
        }
    }

    func tabGroupSources(default service: any BrowserExtensionTabGroupHandling)
        -> [BrowserExtensionTabGroupRoutingService.Source]
    {
        var result: [BrowserExtensionTabGroupRoutingService.Source] = [
            .init(service: service, session: browser?.session)
        ]
        var seen: Set<ObjectIdentifier> = [ObjectIdentifier(service)]
        for host in hostWindowOrder.compactMap({ hostWindows[$0] }) {
            guard let browser = host.browser as? BrowserStore,
                seen.insert(ObjectIdentifier(browser.extensionTabGroups)).inserted
            else { continue }
            result.append(.init(service: browser.extensionTabGroups, session: browser.session))
        }
        return result
    }
}
