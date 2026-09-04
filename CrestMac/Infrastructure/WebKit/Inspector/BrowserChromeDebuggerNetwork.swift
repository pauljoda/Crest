import Foundation

/// Converts WebKit's `Network` domain into the four CDP events a client needs
/// to watch a page load. WebKit and Chrome agree on request identity and on
/// monotonic seconds, so the translation is shape, not bookkeeping — except for
/// the resource type, which Chrome repeats on `loadingFailed` and WebKit only
/// ever states once.
@MainActor
final class BrowserChromeDebuggerNetwork {
    var onEvent: ((String, [String: Any]) -> Void)?

    private let connection: BrowserWebInspectorProtocolConnection
    private var enabledAttachment: UUID?
    /// The last resource type seen per request, so a failure can name it.
    private var resourceTypes: [String: String] = [:]

    private var isEnabled: Bool {
        enabledAttachment != nil && enabledAttachment == connection.attachmentIdentifier
    }

    init(connection: BrowserWebInspectorProtocolConnection) {
        self.connection = connection
    }

    func execute(_ method: String, parameters: [String: Any]) async throws -> [String: Any] {
        try Task.checkCancellation()
        guard connection.isConnected else { throw BrowserWebInspectorProtocolError.notConnected }
        switch method {
        case "Network.enable":
            try await enable()
            return [:]
        case "Network.disable":
            disable()
            return [:]
        case "Network.getResponseBody":
            guard let requestID = parameters["requestId"] as? String else {
                throw BrowserChromeDebuggerProtocolError.invalidParameter("requestId")
            }
            return try await connection.sendCommand(
                "Network.getResponseBody", parameters: ["requestId": requestID])
        default:
            throw BrowserChromeDebuggerProtocolError.unsupportedCommand(method)
        }
    }

    /// Stops forwarding without disabling WebKit's own domain, which Inspector
    /// enabled for the frontend this transport borrows.
    func disable() {
        enabledAttachment = nil
        resourceTypes.removeAll()
    }

    func receive(_ method: String, parameters: [String: Any]) {
        guard isEnabled else { return }
        switch method {
        case "Network.requestWillBeSent":
            publishRequest(parameters)
        case "Network.responseReceived":
            publishResponse(parameters)
        case "Network.loadingFinished":
            publishFinished(parameters)
        case "Network.loadingFailed":
            publishFailed(parameters)
        default:
            return
        }
    }

    private func enable() async throws {
        guard let attachment = connection.attachmentIdentifier else {
            throw BrowserWebInspectorProtocolError.notConnected
        }
        if enabledAttachment == attachment { return }
        _ = try await connection.sendCommand("Network.enable")
        enabledAttachment = attachment
    }

    private func publishRequest(_ parameters: [String: Any]) {
        guard let requestID = parameters["requestId"] as? String,
            let request = parameters["request"] as? [String: Any]
        else { return }
        let type = resourceType(parameters["type"])
        if let type { resourceTypes[requestID] = type }
        var event: [String: Any] = [
            "requestId": requestID,
            "loaderId": parameters["loaderId"] as? String ?? "",
            "documentURL": parameters["documentURL"] as? String ?? "",
            "request": chromeRequest(request),
            "timestamp": parameters["timestamp"] as? Double ?? 0,
            "wallTime": parameters["walltime"] as? Double ?? 0,
            "initiator": chromeInitiator(parameters["initiator"] as? [String: Any]),
            // Crest never reports the extra CORS/cache detail Chrome sends on a
            // second channel, so a client must not wait for it.
            "redirectHasExtraInfo": false,
        ]
        if let frameID = parameters["frameId"] as? String { event["frameId"] = frameID }
        if let type { event["type"] = type }
        if let redirect = parameters["redirectResponse"] as? [String: Any] {
            event["redirectResponse"] = chromeResponse(redirect)
        }
        onEvent?("Network.requestWillBeSent", event)
    }

    private func publishResponse(_ parameters: [String: Any]) {
        guard let requestID = parameters["requestId"] as? String,
            let response = parameters["response"] as? [String: Any]
        else { return }
        let type = resourceType(parameters["type"]) ?? resourceTypes[requestID] ?? "Other"
        resourceTypes[requestID] = type
        var event: [String: Any] = [
            "requestId": requestID,
            "loaderId": parameters["loaderId"] as? String ?? "",
            "timestamp": parameters["timestamp"] as? Double ?? 0,
            "type": type,
            "response": chromeResponse(response),
            "hasExtraInfo": false,
        ]
        if let frameID = parameters["frameId"] as? String { event["frameId"] = frameID }
        onEvent?("Network.responseReceived", event)
    }

    private func publishFinished(_ parameters: [String: Any]) {
        guard let requestID = parameters["requestId"] as? String else { return }
        resourceTypes[requestID] = nil
        let metrics = parameters["metrics"] as? [String: Any]
        onEvent?(
            "Network.loadingFinished",
            [
                "requestId": requestID,
                "timestamp": parameters["timestamp"] as? Double ?? 0,
                "encodedDataLength": metrics?["responseBodyBytesReceived"] as? Double ?? 0,
            ])
    }

    private func publishFailed(_ parameters: [String: Any]) {
        guard let requestID = parameters["requestId"] as? String else { return }
        let type = resourceTypes.removeValue(forKey: requestID) ?? "Other"
        var event: [String: Any] = [
            "requestId": requestID,
            "timestamp": parameters["timestamp"] as? Double ?? 0,
            "type": type,
            "errorText": parameters["errorText"] as? String ?? "",
        ]
        if let canceled = parameters["canceled"] as? Bool { event["canceled"] = canceled }
        onEvent?("Network.loadingFailed", event)
    }

    private func chromeRequest(_ request: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [
            "url": request["url"] as? String ?? "",
            "method": request["method"] as? String ?? "GET",
            "headers": request["headers"] as? [String: Any] ?? [:],
            // WebKit reports no per-request priority; Chrome requires one.
            "initialPriority": "Medium",
            "referrerPolicy": referrerPolicy(request["referrerPolicy"] as? String),
        ]
        if let postData = request["postData"] as? String {
            result["postData"] = postData
            result["hasPostData"] = true
        }
        return result
    }

    private func chromeResponse(_ response: [String: Any]) -> [String: Any] {
        let source = response["source"] as? String
        var result: [String: Any] = [
            "url": response["url"] as? String ?? "",
            "status": response["status"] as? Int ?? 0,
            "statusText": response["statusText"] as? String ?? "",
            "headers": response["headers"] as? [String: Any] ?? [:],
            "mimeType": response["mimeType"] as? String ?? "",
            // WebKit states none of the connection detail Chrome requires here.
            "charset": "",
            "connectionReused": false,
            "connectionId": 0,
            "encodedDataLength": -1,
            "securityState": response["security"] == nil ? "unknown" : "secure",
        ]
        if source == "disk-cache" { result["fromDiskCache"] = true }
        if source == "service-worker" { result["fromServiceWorker"] = true }
        if let requestHeaders = response["requestHeaders"] as? [String: Any] {
            result["requestHeaders"] = requestHeaders
        }
        return result
    }

    private func chromeInitiator(_ initiator: [String: Any]?) -> [String: Any] {
        guard let initiator else { return ["type": "other"] }
        var result: [String: Any] = ["type": initiator["type"] as? String ?? "other"]
        if let stack = initiator["stackTrace"] as? [String: Any] {
            result["stack"] = BrowserChromeDebuggerValues.stackTrace(stack)
        }
        if let url = initiator["url"] as? String { result["url"] = url }
        if let line = initiator["lineNumber"] {
            result["lineNumber"] = BrowserChromeDebuggerValues.zeroBasedPosition(line)
        }
        return result
    }

    /// WebKit spells the stylesheet type with a capital S and reports beacons
    /// separately; Chrome has neither spelling.
    private func resourceType(_ value: Any?) -> String? {
        guard let type = value as? String else { return nil }
        switch type {
        case "StyleSheet": return "Stylesheet"
        case "Beacon": return "Ping"
        case "Document", "Image", "Font", "Script", "XHR", "Fetch", "Ping", "WebSocket", "EventSource", "Other":
            return type
        default: return "Other"
        }
    }

    private func referrerPolicy(_ value: String?) -> String {
        // WebKit spells the unset policy `empty-string`; Chrome has no such case.
        guard let value, value != "empty-string" else { return "strict-origin-when-cross-origin" }
        return value
    }
}
