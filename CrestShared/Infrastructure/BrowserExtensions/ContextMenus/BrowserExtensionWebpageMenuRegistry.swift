import Foundation

enum BrowserExtensionWebpageMenuRegistryError: Error, Equatable {
    case invalidReplacement
}

enum BrowserExtensionInstallLifecycleReason: String, Equatable, Sendable {
    case install
    case update
}

private struct BrowserExtensionInstallLifecycleEvent: Equatable {
    let id: String
    let reason: BrowserExtensionInstallLifecycleReason
    let previousVersion: String?

    var message: [String: Any] {
        var message: [String: Any] = [
            "api": "runtime.onInstalled",
            "eventID": id,
            "reason": reason.rawValue,
        ]
        message["previousVersion"] = previousVersion
        return message
    }
}

@MainActor
final class BrowserExtensionWebpageMenuRegistry {
    typealias ClickPublisher = ([String: Any]) -> Void

    private struct PendingClick {
        let id: UUID
        let message: [String: Any]
    }

    private var definitionsByClient: [BrowserExtensionServiceClientID: [BrowserExtensionWebpageMenuDefinition]] = [:]
    private var clickPublishersByClient: [BrowserExtensionServiceClientID: [UUID: ClickPublisher]] = [:]
    private var pendingClicksByClient: [BrowserExtensionServiceClientID: [PendingClick]] = [:]
    private var pendingClickExpirationTasks: [BrowserExtensionServiceClientID: [UUID: Task<Void, Never>]] = [:]
    private var pendingInstallLifecycleByClient:
        [BrowserExtensionServiceClientID: BrowserExtensionInstallLifecycleEvent] = [:]

    @discardableResult
    func prepareInstallLifecycle(
        reason: BrowserExtensionInstallLifecycleReason,
        previousVersion: String?,
        for clientID: BrowserExtensionServiceClientID
    ) -> String {
        let event = BrowserExtensionInstallLifecycleEvent(
            id: UUID().uuidString.lowercased(),
            reason: reason,
            previousVersion: previousVersion
        )
        pendingInstallLifecycleByClient[clientID] = event
        return event.id
    }

    func pendingInstallLifecycleMessage(
        for clientID: BrowserExtensionServiceClientID
    ) -> [String: Any]? {
        pendingInstallLifecycleByClient[clientID]?.message
    }

    @discardableResult
    func acknowledgeInstallLifecycle(
        eventID: String,
        for clientID: BrowserExtensionServiceClientID
    ) -> Bool {
        guard pendingInstallLifecycleByClient[clientID]?.id == eventID else {
            return false
        }
        pendingInstallLifecycleByClient[clientID] = nil
        return true
    }

    func cancelInstallLifecycle(
        eventID: String,
        for clientID: BrowserExtensionServiceClientID
    ) {
        _ = acknowledgeInstallLifecycle(eventID: eventID, for: clientID)
    }

    func replaceDefinitions(
        message: Any,
        for clientID: BrowserExtensionServiceClientID
    ) throws {
        definitionsByClient[clientID] = []
        guard let request = message as? [String: Any],
            request["api"] as? String == "contextMenus.replace",
            let items = request["items"] as? [[String: Any]]
        else {
            throw BrowserExtensionWebpageMenuRegistryError.invalidReplacement
        }
        let definitions = try items.map(Self.definition(from:))
        let ids = definitions.map(\.id)
        guard Set(ids).count == ids.count,
            definitions.allSatisfy({ definition in
                guard let parentID = definition.parentID else { return true }
                return ids.contains(parentID)
            })
        else {
            throw BrowserExtensionWebpageMenuRegistryError.invalidReplacement
        }
        definitionsByClient[clientID] = definitions
    }

    func definitions(
        for clientID: BrowserExtensionServiceClientID
    ) -> [BrowserExtensionWebpageMenuDefinition] {
        definitionsByClient[clientID] ?? []
    }

    func restorationMessage(
        for clientID: BrowserExtensionServiceClientID
    ) -> [String: Any]? {
        let definitions = definitions(for: clientID)
        guard !definitions.isEmpty else { return nil }
        let items = definitions.map { definition -> [String: Any] in
            var item: [String: Any] = [
                "id": definition.id,
                "type": definition.type.rawValue,
                "title": definition.title,
                "contexts": definition.contexts.sorted(),
                "documentUrlPatterns": definition.documentURLPatterns,
                "targetUrlPatterns": definition.targetURLPatterns,
                "enabled": definition.enabled,
                "visible": definition.visible,
            ]
            item["parentId"] = definition.parentID
            return item
        }
        return [
            "api": "contextMenus.restore",
            "items": items,
        ]
    }

    func observeClicks(
        for clientID: BrowserExtensionServiceClientID,
        publish: @escaping ClickPublisher
    ) -> UUID {
        let token = UUID()
        clickPublishersByClient[clientID, default: [:]][token] = publish
        let pendingClicks =
            pendingClicksByClient.removeValue(forKey: clientID)
            ?? []
        for pendingClick in pendingClicks {
            pendingClickExpirationTasks[clientID]?[pendingClick.id]?.cancel()
            pendingClickExpirationTasks[clientID]?[pendingClick.id] = nil
            publish(pendingClick.message)
        }
        if pendingClickExpirationTasks[clientID]?.isEmpty == true {
            pendingClickExpirationTasks[clientID] = nil
        }
        return token
    }

    func removeClickObserver(
        _ token: UUID,
        for clientID: BrowserExtensionServiceClientID
    ) {
        clickPublishersByClient[clientID]?[token] = nil
        if clickPublishersByClient[clientID]?.isEmpty == true {
            clickPublishersByClient[clientID] = nil
        }
    }

    func publishClick(
        menuItemID: String,
        context: BrowserExtensionWebpageMenuContext,
        for clientID: BrowserExtensionServiceClientID
    ) {
        var message: [String: Any] = [
            "api": "contextMenus.click",
            "menuItemID": menuItemID,
            "pageURL": context.pageURL.absoluteString,
            "documentURL": context.documentURL.absoluteString,
            "editable": context.isEditable,
            "mainFrame": context.isMainFrame,
        ]
        message["linkURL"] = context.linkURL?.absoluteString
        message["sourceURL"] = context.sourceURL?.absoluteString
        message["selectionText"] = context.selectionText
        message["mediaType"] = context.sourceURL == nil ? nil : "image"
        let publishers =
            clickPublishersByClient[clientID]?.values.map({ $0 })
            ?? []
        guard publishers.isEmpty else {
            for publisher in publishers {
                publisher(message)
            }
            return
        }
        let pendingClick = PendingClick(id: UUID(), message: message)
        pendingClicksByClient[clientID, default: []].append(pendingClick)
        pendingClickExpirationTasks[clientID, default: [:]][pendingClick.id] =
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.expirePendingClick(pendingClick.id, for: clientID)
            }
    }

    private func expirePendingClick(
        _ pendingClickID: UUID,
        for clientID: BrowserExtensionServiceClientID
    ) {
        pendingClicksByClient[clientID]?.removeAll {
            $0.id == pendingClickID
        }
        if pendingClicksByClient[clientID]?.isEmpty == true {
            pendingClicksByClient[clientID] = nil
        }
        pendingClickExpirationTasks[clientID]?[pendingClickID] = nil
        if pendingClickExpirationTasks[clientID]?.isEmpty == true {
            pendingClickExpirationTasks[clientID] = nil
        }
    }

    func removeClient(_ clientID: BrowserExtensionServiceClientID) {
        definitionsByClient[clientID] = nil
        clickPublishersByClient[clientID] = nil
        pendingClicksByClient[clientID] = nil
        if let tasks = pendingClickExpirationTasks.removeValue(forKey: clientID) {
            for task in tasks.values {
                task.cancel()
            }
        }
    }

    private static func definition(
        from item: [String: Any]
    ) throws -> BrowserExtensionWebpageMenuDefinition {
        guard let id = item["id"] as? String,
            !id.isEmpty,
            let typeName = item["type"] as? String,
            let type = BrowserExtensionWebpageMenuItemType(rawValue: typeName),
            let title = item["title"] as? String,
            let contexts = item["contexts"] as? [String],
            !contexts.isEmpty,
            contexts.allSatisfy(Self.supportedContexts.contains),
            let documentURLPatterns = item["documentUrlPatterns"] as? [String],
            let targetURLPatterns = item["targetUrlPatterns"] as? [String],
            let enabled = item["enabled"] as? Bool,
            let visible = item["visible"] as? Bool
        else {
            throw BrowserExtensionWebpageMenuRegistryError.invalidReplacement
        }
        let parentID: String?
        if let parent = item["parentId"] {
            guard let encodedParent = parent as? String,
                !encodedParent.isEmpty
            else {
                throw BrowserExtensionWebpageMenuRegistryError
                    .invalidReplacement
            }
            parentID = encodedParent
        } else {
            parentID = nil
        }
        return BrowserExtensionWebpageMenuDefinition(
            id: id,
            parentID: parentID,
            type: type,
            title: title,
            contexts: Set(contexts),
            documentURLPatterns: documentURLPatterns,
            targetURLPatterns: targetURLPatterns,
            enabled: enabled,
            visible: visible
        )
    }

    private static let supportedContexts: Set<String> = [
        "all",
        "editable",
        "frame",
        "image",
        "link",
        "page",
        "selection",
        "tab",
    ]
}
