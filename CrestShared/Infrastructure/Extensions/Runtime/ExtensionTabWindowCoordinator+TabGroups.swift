import Foundation
import WebKit

extension BrowserExtensionTabWindowCoordinator {
    /// The wire shape of one `TabGroup`, minus `windowId`.
    ///
    /// The window is deliberately absent. Crest never mints a WebKit window
    /// identifier of its own — the compatibility runtime asks the native
    /// `windows.getCurrent()` for it, exactly as the sidebar fragment does —
    /// so the broker names the window by kind and lets JavaScript supply the
    /// number WebKit actually issued.
    static func tabGroupPayload(_ group: BrowserExtensionTabGroup) -> [String: Any] {
        var payload: [String: Any] = [
            "id": group.id.rawValue,
            "collapsed": group.isCollapsed,
            "color": group.color.rawValue,
            // Chrome's saved/shared groups are a sync feature Crest has no
            // equivalent for. Reporting `false` is the truth, not a stub.
            "shared": false,
        ]
        if let title = group.title { payload["title"] = title }
        return payload
    }

    func tabGroupEventMessage(_ event: BrowserExtensionTabGroupEvent) -> [String: Any] {
        [
            "api": "tabGroups.event", "kind": event.kind.rawValue, "windowKind": "primary",
            "group": Self.tabGroupPayload(event.group),
        ]
    }

    func handleCapabilityBrokerTabGroups(
        _ message: Any, applicationIdentifier: String?, controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext, replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) -> Bool {
        guard applicationIdentifier == BrowserExtensionNativeMessagingApplication.capabilityBrokerIdentifier,
            let payload = message as? [String: Any], let api = payload["api"] as? String,
            BrowserExtensionTabGroupBrokerRequest.Operation(rawValue: api) != nil
        else { return false }
        do {
            let request = try BrowserExtensionTabGroupBrokerRequest(message: payload)
            guard let authorization = verifiedNativeMessagingAuthorizations[ObjectIdentifier(extensionContext)]
            else {
                throw BrowserExtensionNativeMessagingError.unverifiedExtension
            }
            guard authorization.allowsInternalCapabilityBroker else {
                throw BrowserExtensionNativeMessagingError.unverifiedExtension
            }
            if let capability = request.requiredCapability, !authorization.grants(capability) {
                throw BrowserExtensionCapabilityBrokerError.permissionDenied(capability)
            }
            guard let (spaceID, _) = verifiedSpaceAndEntry(controller: controller, context: extensionContext),
                let service = tabGroupService, let state = currentState?.space(spaceID)
            else {
                throw BrowserExtensionTabGroupBrokerError.unavailable
            }
            if let client = authorization.clientID { service.register(client: client, spaceID: spaceID) }
            // A Peek is announced to extensions but is not a session tab, so
            // it can never join a group.
            let liveTabs = Set(state.tabs.map(\.id)).subtracting(
                (transientTabsBySpace[spaceID] ?? []).map(\.id)
            )
            replyHandler(
                try tabGroupResponse(request, service: service, space: state, liveTabs: liveTabs), nil)
        } catch {
            replyHandler(nil, error)
        }
        return true
    }

    private func tabGroupResponse(
        _ request: BrowserExtensionTabGroupBrokerRequest,
        service: any BrowserExtensionTabGroupHandling,
        space: BrowserExtensionSpaceState, liveTabs: Set<TabID>
    ) throws -> [String: Any] {
        switch request.operation {
        case .get:
            return ["group": Self.tabGroupPayload(try group(request, service: service, in: space.id))]
        case .query:
            return [
                "groups": service.groups(in: space.id).filter(request.filter.matches)
                    .map(Self.tabGroupPayload)
            ]
        case .update:
            let existing = try group(request, service: service, in: space.id)
            let updated = try service.update(
                existing.id, in: space.id, title: request.title, color: request.color,
                isCollapsed: request.isCollapsed)
            return ["group": Self.tabGroupPayload(updated)]
        case .move:
            let existing = try group(request, service: service, in: space.id)
            guard let index = request.index else { throw BrowserExtensionTabGroupBrokerError.invalidRequest }
            let moved = try service.move(existing.id, in: space.id, to: index)
            reconcileCurrentSession()
            return ["group": Self.tabGroupPayload(moved)]
        case .membership:
            let membership = membershipPayload(service: service, space: space)
            return [
                "membership": membership, "revision": service.revision,
                "tabs": space.tabs.filter { auxiliaryWindowByTabID[$0.id] == nil }.map {
                    ["tabIndex": $0.index, "tabToken": $0.id.rawValue.uuidString] as [String: Any]
                },
            ]
        case .group:
            let tabs = try request.resolveTabs(in: space, liveTabs: liveTabs)
            let existingID = try request.groupID.map { _ in
                try group(request, service: service, in: space.id).id
            }
            let created = try service.group(tabs, in: space.id, into: existingID)
            reconcileCurrentSession()
            return [
                "groupId": created.id.rawValue,
                "membership": membershipPayload(service: service, space: currentState?.space(space.id) ?? space),
            ]
        case .ungroup:
            service.ungroup(try request.resolveTabs(in: space, liveTabs: liveTabs), in: space.id)
            reconcileCurrentSession()
            return ["membership": membershipPayload(service: service, space: currentState?.space(space.id) ?? space)]
        }
    }

    private func group(
        _ request: BrowserExtensionTabGroupBrokerRequest,
        service: any BrowserExtensionTabGroupHandling, in spaceID: SpaceID
    ) throws -> BrowserExtensionTabGroup {
        guard let groupID = request.groupID else {
            throw BrowserExtensionTabGroupBrokerError.invalidRequest
        }
        guard let group = try? service.group(.init(rawValue: groupID), in: spaceID) else {
            throw BrowserExtensionTabGroupBrokerError.unknownGroup(groupID)
        }
        return group
    }

    /// `Tab.groupId` for the whole Space, addressed the way the wire addresses
    /// every tab: by its index in the primary window.
    private func membershipPayload(
        service: any BrowserExtensionTabGroupHandling, space: BrowserExtensionSpaceState
    ) -> [[String: Any]] {
        let membership = service.membership(in: space.id)
        return space.tabs.compactMap { tab in
            guard let groupID = membership[tab.id] else { return nil }
            return ["tabIndex": tab.index, "groupId": groupID.rawValue]
        }
    }
}
