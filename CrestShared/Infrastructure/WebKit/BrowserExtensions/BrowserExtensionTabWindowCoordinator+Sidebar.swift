import Foundation
import WebKit
import os

private let browserExtensionSidebarLog = Logger(
    subsystem: ProductIdentity.serviceNamespace,
    category: "extension-sidebar"
)

extension BrowserExtensionTabWindowCoordinator {
    func sidebarIsAvailable(for context: WKWebExtensionContext) -> Bool {
        guard let client = sidebarClientsByContext[ObjectIdentifier(context)], let service = sidebarService,
            let controller = context.webExtensionController,
            let (spaceID, _) = verifiedSpaceAndEntry(controller: controller, context: context),
            service.hostWindow(for: spaceID) != nil,
            let options = try? service.resolvedOptions(for: currentState?.space(spaceID)?.selectedTabID, client: client)
        else { return false }
        return options.presentsPanel
    }

    func sidebarIsOpen(for context: WKWebExtensionContext) -> Bool {
        guard let client = sidebarClientsByContext[ObjectIdentifier(context)], let service = sidebarService,
            let controller = context.webExtensionController,
            let (spaceID, _) = verifiedSpaceAndEntry(controller: controller, context: context),
            let window = service.hostWindow(for: spaceID)
        else { return false }
        return service.isOpen(for: client, in: window)
    }

    @discardableResult
    func performSidebarAction(for context: WKWebExtensionContext, invocation: BrowserExtensionSidebarInvocation) -> Bool
    {
        guard let client = sidebarClientsByContext[ObjectIdentifier(context)], let service = sidebarService,
            let flavor = service.flavor(for: client), let controller = context.webExtensionController,
            let (spaceID, _) = verifiedSpaceAndEntry(controller: controller, context: context),
            let window = service.hostWindow(for: spaceID),
            BrowserExtensionSidebarActionPolicy.intercepts(
                invocation, flavor: flavor,
                opensOnAction: (try? service.behavior(for: client).openPanelOnActionClick) == true,
                hasPanel: sidebarIsAvailable(for: context))
        else { return false }
        let selectedTab = currentState?.space(spaceID)?.selectedTabID
        noteUserGesture(for: client)
        if let selectedTab, let adapter = tab(for: selectedTab, in: spaceID) {
            context.userGesturePerformed(in: adapter)
        }
        do {
            try service.toggle(for: client, in: window, tab: selectedTab)
            return true
        } catch { return false }
    }

    func noteUserGesture(for context: WKWebExtensionContext) {
        guard let client = sidebarClientsByContext[ObjectIdentifier(context)] else { return }
        noteUserGesture(for: client)
    }

    func noteUserGesture(for client: BrowserExtensionServiceClientID) {
        sidebarUserGestures.note(for: client, now: ProcessInfo.processInfo.systemUptime)
    }

    func sidebarEventMessage(_ event: BrowserExtensionSidebarEvent) -> [String: Any]? {
        var message: [String: Any] = [
            "api": "sidebar.event", "kind": event.kind.rawValue,
            "windowKind": "primary", "path": event.path,
        ]
        if let tabID = event.tabID {
            guard let tab = currentState?.space(event.spaceID)?.tab(tabID) else { return nil }
            message["tabIndex"] = tab.index
            message["url"] = tab.url?.absoluteString
        }
        return message
    }

    func handleCapabilityBrokerSidebar(
        _ message: Any, applicationIdentifier: String?, controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext, replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) -> Bool {
        guard applicationIdentifier == BrowserExtensionNativeMessagingApplication.capabilityBrokerIdentifier,
            let payload = message as? [String: Any], let api = payload["api"] as? String,
            BrowserExtensionSidebarBrokerRequest.Operation(rawValue: api) != nil
        else { return false }
        do {
            let request = try BrowserExtensionSidebarBrokerRequest(message: payload)
            guard let authorization = verifiedNativeMessagingAuthorizations[ObjectIdentifier(extensionContext)] else {
                throw BrowserExtensionNativeMessagingError.unverifiedExtension
            }
            guard authorization.allowsInternalCapabilityBroker, authorization.grants(request.requiredCapability) else {
                throw BrowserExtensionCapabilityBrokerError.permissionDenied(request.requiredCapability)
            }
            guard let (spaceID, _) = verifiedSpaceAndEntry(controller: controller, context: extensionContext),
                let client = sidebarClientsByContext[ObjectIdentifier(extensionContext)],
                let service = sidebarService, let state = currentState?.space(spaceID)
            else {
                throw BrowserExtensionSidebarError.unavailable
            }
            let liveTabs = Set(state.tabs.map(\.id)).subtracting(
                (transientTabsBySpace[spaceID] ?? []).map(\.id)
            )
            let scope: BrowserExtensionSidebarScope
            do {
                scope = try request.resolveScope(in: state, liveTabs: liveTabs)
            } catch BrowserExtensionSidebarBrokerError.staleTab {
                if case .tab(let index, let url) = request.target {
                    let stateURL = state.tabs.first(where: { $0.index == index })?.url?.absoluteString ?? "<no tab at index>"
                    browserExtensionSidebarLog.error(
                        "\(api, privacy: .public) stale tab: index \(index, privacy: .public) requested \(url ?? "<nil>", privacy: .public) state \(stateURL, privacy: .public)"
                    )
                }
                throw BrowserExtensionSidebarBrokerError.staleTab
            }
            if request.requiresUserGesture, !request.userActivation,
                !sidebarUserGestures.hasRecentGesture(for: client, now: ProcessInfo.processInfo.systemUptime)
            {
                throw BrowserExtensionSidebarBrokerError.userGesture(api)
            }
            let response = try sidebarResponse(
                request, scope: scope, service: service, client: client, space: state, baseURL: extensionContext.baseURL
            )
            browserExtensionSidebarLog.info(
                "\(extensionContext.webExtension.displayName ?? "extension", privacy: .public) \(api, privacy: .public) ok"
            )
            replyHandler(response, nil)
        } catch {
            browserExtensionSidebarLog.error(
                "\(extensionContext.webExtension.displayName ?? "extension", privacy: .public) \(api, privacy: .public) failed: \(String(describing: error), privacy: .public)"
            )
            replyHandler(nil, error)
        }
        return true
    }

    private func sidebarResponse(
        _ request: BrowserExtensionSidebarBrokerRequest, scope: BrowserExtensionSidebarScope,
        service: any BrowserExtensionSidebarHandling, client: BrowserExtensionServiceClientID,
        space: BrowserExtensionSpaceState, baseURL: URL
    ) throws -> [String: Any] {
        let tab: TabID? = if case .tab(let tab) = scope { tab } else { nil }
        switch request.operation {
        case .setOptions:
            try service.setChromeOptions(.init(path: request.path, isEnabled: request.enabled), tab: tab, from: client)
        case .getOptions:
            // Chrome returns a stored layer, falling back to the default layer
            // and then the manifest. It does not invent a tabId on fallback.
            var layer = try service.layer(scope, for: client)
            let isTabSpecific = tab != nil && layer != .init()
            if layer == .init() { layer = try service.layer(.default, for: client) }
            if layer == .init() {
                let options = try service.resolvedOptions(at: .default, client: client)
                layer = options.path.isEmpty ? .init() : .init(path: options.path, isEnabled: options.isEnabled)
            }
            var result: [String: Any] = ["tabSpecific": isTabSpecific]
            result["path"] = layer.path
            result["enabled"] = layer.isEnabled
            return result
        case .setBehavior:
            if let value = request.openPanelOnActionClick {
                try service.setBehavior(.init(openPanelOnActionClick: value), from: client)
            }
        case .getBehavior:
            return ["openPanelOnActionClick": try service.behavior(for: client).openPanelOnActionClick]
        case .setPanel:
            try service.setOptions(.init(path: request.path), scope: scope, from: client)
        case .getPanel:
            let options = try service.resolvedOptions(at: scope, client: client)
            return [
                "panel": options.path.isEmpty
                    ? ""
                    : BrowserExtensionSidebarResourcePolicy.documentURL(
                        path: options.path, baseURL: baseURL
                    )?.absoluteString ?? ""
            ]
        case .setTitle:
            if request.clearsTitle {
                try service.clearTitle(scope: scope, from: client)
            } else {
                try service.setOptions(.init(title: request.title), scope: scope, from: client)
            }
        case .getTitle:
            return ["title": try service.resolvedOptions(at: scope, client: client).title]
        case .setIcon:
            if request.clearsIcon {
                try service.clearIcon(scope: scope, from: client)
            } else {
                try service.setOptions(.init(icon: request.icon), scope: scope, from: client)
            }
        case .layout:
            return ["side": sidebarLayoutSide()]
        case .open, .close, .sidebarOpen, .sidebarClose, .sidebarToggle, .isOpen:
            guard let window = service.hostWindow(for: space.id) else { throw BrowserExtensionSidebarError.unavailable }
            switch request.operation {
            case .open: try service.open(for: client, in: window, tab: tab)
            case .close: try service.closeChromePanel(for: client, in: window, tab: tab)
            case .sidebarOpen: try service.open(for: client, in: window, tab: space.selectedTabID)
            case .sidebarClose: try service.close(for: client, in: window, tab: nil)
            case .sidebarToggle: try service.toggle(for: client, in: window, tab: space.selectedTabID)
            case .isOpen: return ["isOpen": service.isOpen(for: client, in: window)]
            default: break
            }
        }
        return ["ok": true]
    }
}
