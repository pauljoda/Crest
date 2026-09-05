import Foundation

/// One native document binding and node-identity map per debugger attachment.
/// All document readers must share it: WebKit's getDocument resets bindings,
/// and independently generated backend IDs could point at unrelated elements.
@MainActor
final class BrowserChromeDebuggerDOM {
    private let connection: BrowserWebInspectorProtocolConnection
    private var attachment: UUID?
    private(set) var rootNodeID: Int?
    private var documentRequest: Task<Int, Error>?
    private(set) var generation = 0
    private var sequence = 0
    private(set) var snapshotRegistryKey = UUID().uuidString
    private struct WeakNode: Hashable {
        let contextID: Int
        let identifier: Int
    }
    private var weakToClient: [WeakNode: Int] = [:]
    private var clientToWeak: [Int: WeakNode] = [:]
    private var engineToClient: [Int: Int] = [:]
    private var clientToEngine: [Int: Int] = [:]
    private var nodes: [Int: [String: Any]] = [:]

    init(connection: BrowserWebInspectorProtocolConnection) { self.connection = connection }

    func activate() throws {
        guard let current = connection.attachmentIdentifier else { throw BrowserWebInspectorProtocolError.notConnected }
        if attachment != current {
            invalidateDocument()
            attachment = current
        }
    }

    func detach() {
        attachment = nil
        invalidateDocument()
    }

    func metadata(for engine: Int) -> [String: Any] { nodes[engine] ?? [:] }
    func engineNode(for identifier: Int) -> Int? { clientToEngine[identifier] }

    func receive(_ method: String, parameters: [String: Any]) {
        if method == "DOM.documentUpdated" { invalidateDocument() }
        if method == "DOM.setChildNodes", let children = parameters["nodes"] as? [[String: Any]] {
            children.forEach(remember)
        }
        if method == "DOM.childNodeInserted", let node = parameters["node"] as? [String: Any] { remember(node) }
        if method == "DOM.characterDataModified", let id = parameters["nodeId"] as? Int {
            nodes[id]?["nodeValue"] = parameters["characterData"]
        }
        if method == "DOM.childNodeRemoved", let id = parameters["nodeId"] as? Int {
            nodes[id] = nil
            if let client = engineToClient.removeValue(forKey: id) { clientToEngine[client] = nil }
        }
    }

    func document() async throws -> Int {
        if let rootNodeID { return rootNodeID }
        if let documentRequest { return try await documentRequest.value }
        let expected = generation
        let request = Task { @MainActor in
            defer { if generation == expected { documentRequest = nil } }
            // getDocument resets WebKit's node bindings. Keep this one document
            // until its native invalidation event, so IDs survive repeated reads.
            let response = try await connection.sendCommand("DOM.getDocument")
            try Task.checkCancellation()
            guard generation == expected else {
                throw BrowserChromeDebuggerProtocolError.invalidParameter("Document changed")
            }
            guard let node = response["root"] as? [String: Any], let id = node["nodeId"] as? Int else {
                throw BrowserChromeDebuggerProtocolError.invalidResult
            }
            remember(node)
            rootNodeID = id
            return id
        }
        documentRequest = request
        return try await request.value
    }

    func resolveNode(_ parameters: [String: Any]) async throws -> [String: Any] {
        for name in ["nodeId", "executionContextId"] where parameters[name] != nil {
            throw BrowserChromeDebuggerProtocolError.unsupportedParameter(name)
        }
        let id = try BrowserChromeDebuggerValues.integer(parameters["backendNodeId"], name: "backendNodeId")
        var request: [String: Any] = [:]
        if let group = parameters["objectGroup"] {
            guard let value = group as? String else {
                throw BrowserChromeDebuggerProtocolError.invalidParameter("objectGroup")
            }
            request["objectGroup"] = value
        }
        if let weak = clientToWeak[id] {
            let response = try await connection.sendCommand(
                "Runtime.evaluate",
                parameters: [
                    "expression":
                        "globalThis.__crestDebuggerNodeRegistry?.key === '\(snapshotRegistryKey)' ? globalThis.__crestDebuggerNodeRegistry.nodes.get(\(weak.identifier))?.deref() : undefined",
                    "contextId": weak.contextID, "returnByValue": false,
                    "objectGroup": request["objectGroup"] ?? "",
                    "doNotPauseOnExceptionsAndMuteConsole": true,
                ])
            guard let object = response["result"] as? [String: Any], object["objectId"] is String else {
                throw BrowserChromeDebuggerProtocolError.invalidParameter("backendNodeId")
            }
            return ["object": BrowserChromeDebuggerValues.remoteObject(object)]
        }
        guard let engine = clientToEngine[id] else {
            throw BrowserChromeDebuggerProtocolError.invalidParameter("backendNodeId")
        }
        request["nodeId"] = engine
        let response = try await connection.sendCommand("DOM.resolveNode", parameters: request)
        guard let object = response["object"] as? [String: Any] else {
            throw BrowserChromeDebuggerProtocolError.invalidResult
        }
        return ["object": BrowserChromeDebuggerValues.remoteObject(object)]
    }

    func identifier(_ engine: Int) -> Int {
        if let id = engineToClient[engine] { return id }
        sequence += 1
        engineToClient[engine] = sequence
        clientToEngine[sequence] = engine
        return sequence
    }

    func weakIdentifier(_ identifier: Int, contextID: Int) -> Int {
        let weak = WeakNode(contextID: contextID, identifier: identifier)
        if let id = weakToClient[weak] { return id }
        sequence += 1
        weakToClient[weak] = sequence
        clientToWeak[sequence] = weak
        return sequence
    }

    private func remember(_ node: [String: Any]) {
        if let id = node["nodeId"] as? Int { nodes[id] = node }
        for key in ["children", "shadowRoots"] { (node[key] as? [[String: Any]] ?? []).forEach(remember) }
        if let document = node["contentDocument"] as? [String: Any] { remember(document) }
    }

    private func invalidateDocument() {
        documentRequest?.cancel()
        documentRequest = nil
        generation += 1
        snapshotRegistryKey = UUID().uuidString
        weakToClient.removeAll()
        clientToWeak.removeAll()
        rootNodeID = nil
        nodes.removeAll()
        engineToClient.removeAll()
        clientToEngine.removeAll()
    }
}
