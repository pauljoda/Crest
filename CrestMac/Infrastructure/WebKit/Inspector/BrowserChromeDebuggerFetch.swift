import Foundation

/// Owns pauses for one debugger attachment. Network IDs are engine identities;
/// each externally visible pause gets a fresh ID, including redirect stages.
@MainActor
final class BrowserChromeDebuggerFetch {
    var onEvent: ((String, [String: Any]) -> Void)?
    private let connection: BrowserWebInspectorProtocolConnection
    private var attachment: UUID?
    private var patterns: [Pattern] = []
    private var installedStages: Set<String> = []
    private var requests: [String: [String: Any]] = [:]
    private var pauses: [String: Pause] = [:]
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let interceptionURL = "^[\\s\\S]*$"

    private struct Pause {
        let networkID: String
        let stage: String
    }

    private struct Pattern {
        let expression: NSRegularExpression
        let resourceType: String?
        let stage: String

        init(_ value: [String: Any]) throws {
            for key in value.keys where !["urlPattern", "resourceType", "requestStage"].contains(key) {
                throw BrowserChromeDebuggerProtocolError.unsupportedParameter(key)
            }
            guard value["urlPattern"] == nil || value["urlPattern"] is String,
                value["resourceType"] == nil || value["resourceType"] is String
            else { throw BrowserChromeDebuggerProtocolError.invalidParameter("patterns") }
            switch value["requestStage"] as? String ?? "Request" {
            case "Request": stage = "request"
            case "Response": stage = "response"
            default: throw BrowserChromeDebuggerProtocolError.invalidParameter("requestStage")
            }
            resourceType = value["resourceType"] as? String
            if let resourceType,
                ![
                    "Document", "Stylesheet", "Image", "Media", "Font", "Script", "TextTrack", "XHR", "Fetch",
                    "Prefetch", "EventSource", "WebSocket", "Manifest", "SignedExchange", "Ping",
                    "CSPViolationReport", "Preflight", "FedCM", "Other",
                ].contains(resourceType)
            {
                throw BrowserChromeDebuggerProtocolError.invalidParameter("resourceType")
            }
            var regex = "\\A"
            var escaped = false
            for character in value["urlPattern"] as? String ?? "*" {
                if escaped {
                    regex += NSRegularExpression.escapedPattern(for: String(character))
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "*" {
                    regex += ".*"
                } else if character == "?" {
                    regex += "."
                } else {
                    regex += NSRegularExpression.escapedPattern(for: String(character))
                }
            }
            if escaped { regex += "\\\\" }
            expression = try NSRegularExpression(pattern: regex + "\\z", options: [.dotMatchesLineSeparators])
        }

        func matches(url: String, type: String, stage: String) -> Bool {
            self.stage == stage && (resourceType == nil || resourceType == type)
                && expression.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
        }
    }

    init(connection: BrowserWebInspectorProtocolConnection) { self.connection = connection }

    func execute(_ method: String, parameters: [String: Any]) async throws -> [String: Any] {
        if busy { await withCheckedContinuation { waiters.append($0) } } else { busy = true }
        defer {
            if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
        }
        try Task.checkCancellation()
        guard connection.isConnected else { throw BrowserWebInspectorProtocolError.notConnected }
        switch method {
        case "Fetch.enable": try await enable(parameters)
        case "Fetch.disable": try await disable()
        case "Fetch.continueRequest", "Fetch.continueResponse": try await resume(method, parameters)
        case "Fetch.failRequest": try await fail(parameters)
        case "Fetch.fulfillRequest": try await fulfill(parameters)
        case "Fetch.getResponseBody":
            let (_, pause) = try paused(parameters)
            guard pause.stage == "response" else {
                throw BrowserChromeDebuggerProtocolError.invalidParameter("requestId")
            }
            return try await connection.sendCommand(
                "Network.getResponseBody", parameters: ["requestId": pause.networkID])
        default: throw BrowserChromeDebuggerProtocolError.unsupportedCommand(method)
        }
        return [:]
    }

    private func enable(_ parameters: [String: Any]) async throws {
        for key in parameters.keys where !["patterns", "handleAuthRequests"].contains(key) {
            throw BrowserChromeDebuggerProtocolError.unsupportedParameter(key)
        }
        if let auth = parameters["handleAuthRequests"] {
            guard let enabled = auth as? Bool else {
                throw BrowserChromeDebuggerProtocolError.invalidParameter("handleAuthRequests")
            }
            if enabled { throw BrowserChromeDebuggerProtocolError.unsupportedParameter("handleAuthRequests") }
        }
        guard parameters["patterns"] == nil || parameters["patterns"] is [[String: Any]] else {
            throw BrowserChromeDebuggerProtocolError.invalidParameter("patterns")
        }
        let next = try (parameters["patterns"] as? [[String: Any]] ?? [[:]]).map(Pattern.init)
        guard let current = connection.attachmentIdentifier else { throw BrowserWebInspectorProtocolError.notConnected }
        if attachment != current { detach() }
        if next.isEmpty {
            try await disable()
            return
        }
        if attachment == nil {
            _ = try await connection.sendCommand("Network.enable")
            try await connection.setNetworkInterceptionHandledByClient(true)
            attachment = current
        }
        do {
            // Install each stage once. Matching stays in this attachment so
            // repeated enable calls can replace patterns without releasing pauses.
            for stage in Set(next.map(\.stage)).subtracting(installedStages) {
                _ = try await connection.sendCommand("Network.addInterception", parameters: rule(stage))
                installedStages.insert(stage)
            }
            patterns = next
            try await connection.setNetworkInterceptionEnabled(true)
        } catch {
            try? await disable()
            throw error
        }
    }

    private func disable() async throws {
        guard attachment != nil else { return }
        try await connection.setNetworkInterceptionEnabled(false)
        for stage in installedStages {
            _ = try await connection.sendCommand("Network.removeInterception", parameters: rule(stage))
        }
        try await connection.setNetworkInterceptionHandledByClient(false)
        detach()
    }

    func detach() {
        attachment = nil
        patterns = []
        installedStages = []
        requests.removeAll()
        pauses.removeAll()
    }

    private func rule(_ stage: String) -> [String: Any] {
        ["url": interceptionURL, "stage": stage, "isRegex": true, "caseSensitive": true]
    }

    func receive(_ method: String, parameters: [String: Any]) {
        guard let attachment, attachment == connection.attachmentIdentifier,
            let networkID = parameters["requestId"] as? String
        else { return }
        switch method {
        case "Network.requestWillBeSent": requests[networkID] = parameters
        case "Network.loadingFinished", "Network.loadingFailed":
            requests[networkID] = nil
            pauses = pauses.filter { $0.value.networkID != networkID }
        case "Network.requestIntercepted": intercept(parameters, networkID: networkID, stage: "request")
        case "Network.responseIntercepted": intercept(parameters, networkID: networkID, stage: "response")
        default: break
        }
    }

    private func intercept(_ parameters: [String: Any], networkID: String, stage: String) {
        let metadata = requests[networkID]
        let request = parameters["request"] as? [String: Any] ?? metadata?["request"] as? [String: Any]
        let rawType = metadata?["type"] as? String ?? "Other"
        let type = rawType == "StyleSheet" ? "Stylesheet" : rawType == "Beacon" ? "Ping" : rawType
        guard let request, let url = request["url"] as? String,
            let frameID = metadata?["frameId"] as? String,
            patterns.contains(where: { $0.matches(url: url, type: type, stage: stage) })
        else {
            let owner = attachment
            Task { @MainActor [weak self] in
                guard let self, owner == self.attachment else { return }
                _ = try? await self.connection.sendCommand(
                    "Network.interceptContinue", parameters: ["requestId": networkID, "stage": stage])
            }
            return
        }
        let id = UUID().uuidString
        pauses[id] = .init(networkID: networkID, stage: stage)
        var chromeRequest = request
        chromeRequest["initialPriority"] = "Medium"
        chromeRequest["referrerPolicy"] = request["referrerPolicy"] as? String ?? "strict-origin-when-cross-origin"
        if chromeRequest["referrerPolicy"] as? String == "empty-string" {
            chromeRequest["referrerPolicy"] = "strict-origin-when-cross-origin"
        }
        var event: [String: Any] = [
            "requestId": id, "networkId": networkID, "frameId": frameID, "request": chromeRequest, "resourceType": type,
        ]
        if let response = parameters["response"] as? [String: Any] {
            event["responseStatusCode"] = response["status"]
            event["responseStatusText"] = response["statusText"]
            event["responseHeaders"] = (response["headers"] as? [String: String] ?? [:]).sorted { $0.key < $1.key }.map
            { ["name": $0.key, "value": $0.value] }
        }
        onEvent?("Fetch.requestPaused", event)
    }

    private func paused(_ parameters: [String: Any]) throws -> (String, Pause) {
        guard attachment == connection.attachmentIdentifier, let id = parameters["requestId"] as? String,
            let pause = pauses[id]
        else { throw BrowserChromeDebuggerProtocolError.invalidParameter("requestId") }
        return (id, pause)
    }

    private func resume(_ method: String, _ parameters: [String: Any]) async throws {
        let (id, pause) = try paused(parameters)
        let overrideKeys = ["url", "method", "postData", "headers"]
        for key in parameters.keys where key != "requestId" && !overrideKeys.contains(key) {
            if key == "interceptResponse", parameters[key] as? Bool == false { continue }
            throw BrowserChromeDebuggerProtocolError.unsupportedParameter(key)
        }
        let overrides = overrideKeys.filter { parameters[$0] != nil }
        if method == "Fetch.continueResponse", pause.stage != "response" {
            throw BrowserChromeDebuggerProtocolError.invalidParameter("requestId")
        }
        if !overrides.isEmpty {
            guard pause.stage == "request" else {
                throw BrowserChromeDebuggerProtocolError.unsupportedParameter(overrides[0])
            }
            var native: [String: Any] = ["requestId": pause.networkID]
            for key in overrides where key != "headers" {
                guard let value = parameters[key] as? String else {
                    throw BrowserChromeDebuggerProtocolError.invalidParameter(key)
                }
                if key == "postData", Data(base64Encoded: value) == nil {
                    throw BrowserChromeDebuggerProtocolError.invalidParameter(key)
                }
                native[key] = value
            }
            if parameters["headers"] != nil { native["headers"] = try headers(parameters["headers"], name: "headers") }
            _ = try await connection.sendCommand("Network.interceptWithRequest", parameters: native)
        } else {
            _ = try await connection.sendCommand(
                "Network.interceptContinue", parameters: ["requestId": pause.networkID, "stage": pause.stage])
        }
        pauses[id] = nil
    }

    private func fail(_ parameters: [String: Any]) async throws {
        let (id, pause) = try paused(parameters)
        guard pause.stage == "request" else {
            throw BrowserChromeDebuggerProtocolError.unsupportedCommand("Fetch.failRequest at response stage")
        }
        let reasons = [
            "Failed": "General", "Aborted": "Cancellation", "TimedOut": "Timeout", "AccessDenied": "AccessControl",
            "BlockedByClient": "Cancellation",
        ]
        guard let reason = parameters["errorReason"] as? String, let native = reasons[reason] else {
            throw BrowserChromeDebuggerProtocolError.unsupportedParameter("errorReason")
        }
        _ = try await connection.sendCommand(
            "Network.interceptRequestWithError", parameters: ["requestId": pause.networkID, "errorType": native])
        pauses[id] = nil
    }

    private func fulfill(_ parameters: [String: Any]) async throws {
        let (id, pause) = try paused(parameters)
        if parameters["binaryResponseHeaders"] != nil {
            throw BrowserChromeDebuggerProtocolError.unsupportedParameter("binaryResponseHeaders")
        }
        guard let status = parameters["responseCode"] as? Int, (100...599).contains(status) else {
            throw BrowserChromeDebuggerProtocolError.invalidParameter("responseCode")
        }
        guard !(300...399).contains(status) else {
            throw BrowserChromeDebuggerProtocolError.unsupportedParameter("responseCode redirect")
        }
        let body = parameters["body"] as? String ?? (pause.stage == "request" ? "" : nil)
        guard let body, Data(base64Encoded: body) != nil else {
            throw BrowserChromeDebuggerProtocolError.invalidParameter("body")
        }
        let headers = try headers(parameters["responseHeaders"] ?? [], name: "responseHeaders")
        let mime =
            headers.first { $0.key.lowercased() == "content-type" }?.value.components(separatedBy: ";").first
            ?? "application/octet-stream"
        let native: [String: Any] = [
            "requestId": pause.networkID, "status": status,
            "statusText": parameters["responsePhrase"] as? String
                ?? HTTPURLResponse.localizedString(forStatusCode: status), "headers": headers, "mimeType": mime,
            "content": body, "base64Encoded": true,
        ]
        _ = try await connection.sendCommand(
            pause.stage == "request" ? "Network.interceptRequestWithResponse" : "Network.interceptWithResponse",
            parameters: native)
        pauses[id] = nil
    }

    private func headers(_ value: Any?, name: String) throws -> [String: String] {
        guard let rows = value as? [[String: String]] else {
            throw BrowserChromeDebuggerProtocolError.invalidParameter(name)
        }
        var result: [String: String] = [:]
        var names: Set<String> = []
        for row in rows {
            guard let key = row["name"], let value = row["value"], !key.isEmpty else {
                throw BrowserChromeDebuggerProtocolError.invalidParameter(name)
            }
            guard names.insert(key.lowercased()).inserted else {
                throw BrowserChromeDebuggerProtocolError.unsupportedParameter(name + " duplicate names")
            }
            result[key] = value
        }
        return result
    }
}
