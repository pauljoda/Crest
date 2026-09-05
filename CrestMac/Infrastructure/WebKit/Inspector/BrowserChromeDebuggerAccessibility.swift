import Foundation

/// Reads WebKit's computed accessibility properties, rather than deriving ARIA
/// roles or accessible names from page script. WebKit exposes DOM-backed AX
/// nodes; anonymous platform AX objects and value/source annotations are not
/// available through its Inspector protocol.
@MainActor
final class BrowserChromeDebuggerAccessibility {
    private let connection: BrowserWebInspectorProtocolConnection
    private let dom: BrowserChromeDebuggerDOM
    private var isEnabled = false

    init(connection: BrowserWebInspectorProtocolConnection, dom: BrowserChromeDebuggerDOM) {
        self.connection = connection
        self.dom = dom
    }

    func detach() { isEnabled = false }

    func execute(_ method: String, parameters: [String: Any]) async throws -> [String: Any] {
        try Task.checkCancellation()
        try dom.activate()
        if method == "Accessibility.disable" {
            detach()
            return [:]
        }
        guard
            [
                "Accessibility.enable", "Accessibility.getFullAXTree", "Accessibility.getRootAXNode",
                "Accessibility.getChildAXNodes",
            ].contains(method)
        else { throw BrowserChromeDebuggerProtocolError.unsupportedCommand(method) }
        if ["Accessibility.getRootAXNode", "Accessibility.getChildAXNodes"].contains(method), !isEnabled {
            throw BrowserChromeDebuggerProtocolError.invalidParameter("Accessibility domain is not enabled")
        }
        let root = try await dom.document()
        let epoch = dom.generation
        let frameID = try await mainFrameID(parameters["frameId"])
        if method == "Accessibility.enable" {
            // This native call enables WebCore's AX cache and computes the
            // document's real accessibility object before answering success.
            _ = try await properties(root, generation: epoch)
            isEnabled = true
            return [:]
        }
        if method == "Accessibility.getRootAXNode" {
            return ["node": project(try await properties(root, generation: epoch), frameID: frameID)]
        }
        if method == "Accessibility.getChildAXNodes" {
            guard let raw = parameters["id"] as? String, let id = Int(raw), let engine = dom.engineNode(for: id) else {
                throw BrowserChromeDebuggerProtocolError.invalidParameter("id")
            }
            let parent = try await properties(engine, generation: epoch)
            var children: [[String: Any]] = []
            for child in parent["childNodeIds"] as? [Int] ?? [] {
                children.append(project(try await properties(child, generation: epoch), frameID: frameID))
            }
            return ["nodes": children]
        }
        var depth = Int.max
        if let value = parameters["depth"] {
            depth = try BrowserChromeDebuggerValues.integer(value, name: "depth")
            guard depth >= 0 else { throw BrowserChromeDebuggerProtocolError.invalidParameter("depth") }
        }
        var queue = [(root, 0)]
        var cursor = 0
        var seen = Set<Int>()
        var result: [[String: Any]] = []
        while cursor < queue.count {
            try Task.checkCancellation()
            let (id, level) = queue[cursor]
            cursor += 1
            guard seen.insert(id).inserted else { continue }
            let value = try await properties(id, generation: epoch)
            result.append(project(value, frameID: frameID))
            if level < depth {
                queue += (value["childNodeIds"] as? [Int] ?? []).map { ($0, level + 1) }
            }
        }
        return ["nodes": result]
    }

    private func mainFrameID(_ requested: Any?) async throws -> String {
        let result = try await connection.sendCommand("Page.getResourceTree")
        guard let tree = result["frameTree"] as? [String: Any],
            let frame = tree["frame"] as? [String: Any], let id = frame["id"] as? String
        else { throw BrowserChromeDebuggerProtocolError.invalidResult }
        if let requested {
            guard let value = requested as? String else {
                throw BrowserChromeDebuggerProtocolError.invalidParameter("frameId")
            }
            guard value == id else { throw BrowserChromeDebuggerProtocolError.unsupportedParameter("frameId") }
        }
        return id
    }

    private func properties(_ id: Int, generation expected: Int) async throws -> [String: Any] {
        guard dom.generation == expected else {
            throw BrowserChromeDebuggerProtocolError.invalidParameter("Document changed")
        }
        let result = try await connection.sendCommand(
            "DOM.getAccessibilityPropertiesForNode", parameters: ["nodeId": id])
        guard dom.generation == expected else {
            throw BrowserChromeDebuggerProtocolError.invalidParameter("Document changed")
        }
        guard let properties = result["properties"] as? [String: Any], properties["nodeId"] as? Int != nil else {
            throw BrowserChromeDebuggerProtocolError.invalidResult
        }
        return properties
    }

    private func project(_ properties: [String: Any], frameID: String) -> [String: Any] {
        let engine = properties["nodeId"] as! Int
        let metadata = dom.metadata(for: engine)
        let nativeRole = properties["role"] as? String ?? ""
        let role: String
        if metadata["nodeType"] as? Int == 9 {
            role = "RootWebArea"
        } else if nativeRole == "text" {
            role = "StaticText"
        } else {
            role = nativeRole.isEmpty ? "generic" : nativeRole
        }
        let label = role == "StaticText" ? metadata["nodeValue"] as? String ?? "" : properties["label"] as? String ?? ""
        let id = dom.identifier(engine)
        var result: [String: Any] = [
            "nodeId": String(id), "backendDOMNodeId": id,
            "ignored": properties["ignored"] as? Bool == true || properties["exists"] as? Bool != true,
            "role": value("role", role), "name": value("computedString", label),
            "childIds": (properties["childNodeIds"] as? [Int] ?? []).map { String(dom.identifier($0)) },
        ]
        if engine == dom.rootNodeID { result["frameId"] = frameID }
        if let parent = properties["parentNodeId"] as? Int { result["parentId"] = String(dom.identifier(parent)) }
        var states: [[String: Any]] = []
        for name in [
            "busy", "disabled", "expanded", "focused", "hidden", "readonly", "required", "selected", "pressed",
        ] {
            if let state = properties[name] as? Bool {
                states.append(["name": name, "value": value("boolean", state)])
            }
        }
        if properties["focused"] != nil { states.append(["name": "focusable", "value": value("boolean", true)]) }
        if let checked = properties["checked"] as? String {
            states.append(["name": "checked", "value": value("tristate", checked)])
        }
        if let level = properties["hierarchyLevel"] ?? properties["headingLevel"] {
            states.append(["name": "level", "value": value("integer", level)])
        }
        result["properties"] = states
        return result
    }

    private func value(_ type: String, _ value: Any) -> [String: Any] { ["type": type, "value": value] }

}
