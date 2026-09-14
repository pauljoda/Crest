import Foundation
import WebKit

extension BrowserExtensionTabWindowCoordinator {
    /// The wire shape of one `TabGroup`, minus `windowId`.
    ///
    /// Crest never mints a WebKit window identifier. The owning payload adds
    /// public geometry so JavaScript can resolve the number WebKit issued.
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

    private func ownedGroupPayload(_ group: BrowserExtensionTabGroup) -> [String: Any] {
        var payload = Self.tabGroupPayload(group)
        payload["window"] =
            brokerWindowDescriptor(group.tabs.first.flatMap { window(for: $0, in: group.spaceID) })
            ?? tabGroupWindowDescriptors[group.id]
        return payload
    }

    func tabGroupEventMessage(_ event: BrowserExtensionTabGroupEvent) -> [String: Any] {
        var result: [String: Any] = [
            "api": "tabGroups.event", "kind": event.kind.rawValue, "windowKind": "primary",
            "group": Self.tabGroupPayload(event.group),
        ]
        result["window"] =
            event.kind == .removed
            ? tabGroupWindowDescriptors[event.group.id]
            : brokerWindowDescriptor(event.group.tabs.first.flatMap { window(for: $0, in: event.group.spaceID) })
        // Every subscribed extension receives this event independently, so
        // retain the last descriptor until all queued deliveries can resolve it.
        return result
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
                let service = tabGroupService
            else {
                throw BrowserExtensionTabGroupBrokerError.unavailable
            }
            let targets = payload["tabs"] as? [[String: Any]] ?? []
            let window = try brokerWindow(in: spaceID, message: targets.first ?? payload)
            for target in targets {
                guard try brokerWindow(in: spaceID, message: target) === window else {
                    throw BrowserExtensionTabGroupBrokerError.invalidRequest
                }
            }
            let state = brokerState(in: spaceID, window: window)
            if let client = authorization.clientID { service.register(client: client, spaceID: spaceID) }
            // A Peek is announced to extensions but is not a session tab, so
            // it can never join a group.
            let liveTabs = Set(state.tabs.map(\.id)).subtracting(
                (transientTabsBySpace[spaceID] ?? []).map(\.id)
            )
            replyHandler(
                try tabGroupResponse(request, service: service, space: state, liveTabs: liveTabs, window: window), nil)
        } catch {
            replyHandler(nil, error)
        }
        return true
    }

    private func tabGroupResponse(
        _ request: BrowserExtensionTabGroupBrokerRequest,
        service: any BrowserExtensionTabGroupHandling,
        space: BrowserExtensionSpaceState, liveTabs: Set<TabID>, window: BrowserExtensionWindowAdapter?
    ) throws -> [String: Any] {
        switch request.operation {
        case .get:
            return ["group": ownedGroupPayload(try group(request, service: service, in: space.id))]
        case .query:
            let available = Set(space.tabs.map(\.id))
            return [
                "groups": service.groups(in: space.id).filter {
                    !$0.tabs.isEmpty && $0.tabs.allSatisfy(available.contains)
                }
                .filter(request.filter.matches)
                .map(ownedGroupPayload)
            ]
        case .update:
            let existing = try group(request, service: service, in: space.id)
            let updated = try service.update(
                existing.id, in: space.id, title: request.title, color: request.color,
                isCollapsed: request.isCollapsed)
            return ["group": ownedGroupPayload(updated)]
        case .move:
            let existing = try group(request, service: service, in: space.id)
            guard let index = request.index else { throw BrowserExtensionTabGroupBrokerError.invalidRequest }
            let owner = existing.tabs.first.flatMap { self.window(for: $0, in: space.id) }
            guard existing.tabs.allSatisfy({ self.window(for: $0, in: space.id) === owner }) else {
                throw BrowserExtensionTabGroupBrokerError.failedToMove
            }
            let moved = try service.move(
                existing.id, in: space.id, to: sessionInsertionIndex(index, in: owner, excluding: Set(existing.tabs)))
            reconcileCurrentSession()
            return ["group": ownedGroupPayload(moved)]
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
                "membership": membershipPayload(service: service, space: brokerState(in: space.id, window: window)),
            ]
        case .ungroup:
            service.ungroup(try request.resolveTabs(in: space, liveTabs: liveTabs), in: space.id)
            reconcileCurrentSession()
            return ["membership": membershipPayload(service: service, space: brokerState(in: space.id, window: window))]
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

    /// `Tab.groupId` for this host window, addressed by its native tab index.
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
