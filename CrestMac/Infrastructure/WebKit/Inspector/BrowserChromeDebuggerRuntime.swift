import Foundation

enum BrowserChromeDebuggerProtocolError: Error, Equatable, LocalizedError {
    case unsupportedCommand(String)
    case unsupportedParameter(String)
    case invalidParameter(String)
    case invalidResult

    var errorDescription: String? {
        switch self {
        case .unsupportedCommand(let method): "Crest does not support the debugger command: \(method)."
        case .unsupportedParameter(let name): "Crest does not support this debugger parameter: \(name)."
        case .invalidParameter(let name): "Invalid debugger parameter: \(name)."
        case .invalidResult: "WebKit returned an invalid debugger response."
        }
    }
}

/// Converts CDP Runtime operations to WebKit's protocol. REPL expressions use
/// WebKit's native syntax and lexical scope; V8-only top-level await and lexical
/// redeclaration remain unavailable. A timeout bounds the response wait, since
/// WebKit exposes no equivalent to V8's hard execution termination.
@MainActor
final class BrowserChromeDebuggerRuntime {
    var onEvent: ((String, [String: Any]) -> Void)?

    private let connection: BrowserWebInspectorProtocolConnection
    private var exceptionSequence = 0
    private struct ContextSubscription: Equatable {
        let id = UUID()
        let attachmentID: UUID
    }
    private var contextSubscription: ContextSubscription?

    init(connection: BrowserWebInspectorProtocolConnection) {
        self.connection = connection
    }

    func execute(_ method: String, parameters: [String: Any]) async throws -> [String: Any] {
        try Task.checkCancellation()
        guard connection.isConnected else { throw BrowserWebInspectorProtocolError.notConnected }
        switch method {
        case "Runtime.enable":
            return try await enableContextEvents()
        case "Runtime.disable":
            contextSubscription = nil
            try await connection.observeExecutionContexts(subscription: nil)
            return [:]
        case "Runtime.evaluate":
            return try await evaluate(parameters)
        case "Runtime.callFunctionOn":
            return try await callFunction(parameters)
        case "Runtime.awaitPromise":
            return try evaluationResult(
                await connection.sendCommand(
                    method,
                    parameters: pick(
                        parameters,
                        [
                            "promiseObjectId", "returnByValue", "generatePreview",
                        ])))
        case "Runtime.getProperties":
            return try await properties(parameters)
        case "Runtime.releaseObject":
            return try await connection.sendCommand(method, parameters: pick(parameters, ["objectId"]))
        case "Runtime.releaseObjectGroup":
            return try await connection.sendCommand(method, parameters: pick(parameters, ["objectGroup"]))
        default:
            throw BrowserChromeDebuggerProtocolError.unsupportedCommand(method)
        }
    }

    /// Inspector model notifications are internal transport events. Do not
    /// forward WebKit's differently shaped Runtime packets as Chrome events.
    func receive(_ method: String, parameters: [String: Any]) {
        guard let contextSubscription,
            contextSubscription.attachmentID == connection.attachmentIdentifier,
            parameters["subscription"] as? String == contextSubscription.id.uuidString
        else { return }
        if method == "Crest.executionContextCreated", let context = parameters["context"] as? [String: Any],
            let id = context["id"] as? Int, let identity = context["identity"] as? String,
            let frameID = context["frameId"] as? String, let origin = context["origin"] as? String,
            let name = context["name"] as? String, let type = context["type"] as? String
        {
            onEvent?(
                "Runtime.executionContextCreated",
                [
                    "context": [
                        "id": id, "uniqueId": identity, "origin": origin, "name": name,
                        "auxData": [
                            "frameId": frameID, "isDefault": type == "normal",
                            "type": type == "normal" ? "default" : "isolated",
                        ],
                    ]
                ])
        }
        if method == "Crest.executionContextDestroyed", let id = parameters["id"] as? Int,
            let identity = parameters["identity"] as? String
        {
            onEvent?(
                "Runtime.executionContextDestroyed",
                [
                    "executionContextId": id, "executionContextUniqueId": identity,
                ])
        }
    }

    private func enableContextEvents() async throws -> [String: Any] {
        guard let attachmentID = connection.attachmentIdentifier else {
            throw BrowserWebInspectorProtocolError.notConnected
        }
        if contextSubscription?.attachmentID == attachmentID { return [:] }
        let subscription = ContextSubscription(attachmentID: attachmentID)
        contextSubscription = subscription
        do {
            try await connection.observeExecutionContexts(subscription: subscription.id)
        } catch {
            if contextSubscription == subscription { contextSubscription = nil }
            throw error
        }
        return [:]
    }

    private func evaluate(_ parameters: [String: Any]) async throws -> [String: Any] {
        try validateExecutionConstraints(parameters)
        var request = try evaluationParameters(
            parameters,
            additional: [
                "expression", "objectGroup", "includeCommandLineAPI", "contextId",
            ])
        let awaitsPromise = try boolean("awaitPromise", in: parameters)
        let timeout = (parameters["timeout"] as? NSNumber)?.doubleValue ?? 0
        let deadline = timeout > 0 ? Date(timeIntervalSinceNow: timeout / 1_000) : nil
        if awaitsPromise { request["returnByValue"] = false }
        let response = try await connection.sendCommand(
            "Runtime.evaluate", parameters: request,
            responseTimeoutMilliseconds: deadline.map { max(0, $0.timeIntervalSinceNow * 1_000) })
        guard awaitsPromise, response["wasThrown"] as? Bool != true,
            let object = response["result"] as? [String: Any], let objectID = object["objectId"] as? String
        else { return try evaluationResult(response) }

        // WebKit evaluate has no awaitPromise option. Its callFunctionOn does,
        // and correctly preserves both ordinary objects and fulfilled/rejected
        // promises without rewriting the caller's expression or global scope.
        var awaitRequest = pick(parameters, ["returnByValue", "generatePreview"])
        awaitRequest["objectId"] = objectID
        awaitRequest["functionDeclaration"] = "function() { return this; }"
        awaitRequest["awaitPromise"] = true
        let awaited: [String: Any]
        do {
            awaited = try await connection.sendCommand(
                "Runtime.callFunctionOn", parameters: awaitRequest,
                responseTimeoutMilliseconds: deadline.map { max(0, $0.timeIntervalSinceNow * 1_000) })
        } catch {
            _ = try? await connection.sendCommand("Runtime.releaseObject", parameters: ["objectId": objectID])
            throw error
        }
        if (awaited["result"] as? [String: Any])?["objectId"] as? String != objectID {
            _ = try? await connection.sendCommand("Runtime.releaseObject", parameters: ["objectId": objectID])
        }
        return try evaluationResult(awaited)
    }

    private func callFunction(_ parameters: [String: Any]) async throws -> [String: Any] {
        try validateExecutionConstraints(parameters)
        try validateCallArguments(parameters)
        var request = try evaluationParameters(
            parameters,
            additional: [
                "objectId", "functionDeclaration", "arguments", "awaitPromise",
            ])
        guard let contextID = parameters["executionContextId"] else {
            if parameters["objectGroup"] != nil {
                throw BrowserChromeDebuggerProtocolError.unsupportedParameter("objectGroup")
            }
            return try evaluationResult(await connection.sendCommand("Runtime.callFunctionOn", parameters: request))
        }
        guard parameters["objectId"] == nil,
            let number = contextID as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue.isFinite, number.doubleValue > 0,
            number.doubleValue.rounded() == number.doubleValue
        else { throw BrowserChromeDebuggerProtocolError.invalidParameter("executionContextId") }
        var globalRequest = pick(parameters, ["objectGroup"])
        globalRequest["expression"] = "this"
        globalRequest["contextId"] = contextID
        let global = try await connection.sendCommand("Runtime.evaluate", parameters: globalRequest)
        guard let objectID = (global["result"] as? [String: Any])?["objectId"] as? String else {
            throw BrowserChromeDebuggerProtocolError.invalidResult
        }
        request["objectId"] = objectID
        do {
            let response = try await connection.sendCommand("Runtime.callFunctionOn", parameters: request)
            if (response["result"] as? [String: Any])?["objectId"] as? String != objectID {
                _ = try? await connection.sendCommand("Runtime.releaseObject", parameters: ["objectId": objectID])
            }
            return try evaluationResult(response)
        } catch {
            _ = try? await connection.sendCommand("Runtime.releaseObject", parameters: ["objectId": objectID])
            throw error
        }
    }

    private func properties(_ parameters: [String: Any]) async throws -> [String: Any] {
        for name in ["accessorPropertiesOnly", "nonIndexedPropertiesOnly"] {
            if try boolean(name, in: parameters) {
                throw BrowserChromeDebuggerProtocolError.unsupportedParameter(name)
            }
        }
        var response = try await connection.sendCommand(
            "Runtime.getProperties",
            parameters: pick(
                parameters,
                [
                    "objectId", "ownProperties", "generatePreview",
                ]))
        guard let properties = response.removeValue(forKey: "properties") as? [[String: Any]] else {
            throw BrowserChromeDebuggerProtocolError.invalidResult
        }
        response["result"] = properties.map { property in
            var result = property
            for key in ["value", "get", "set", "symbol"] {
                if let remote = property[key] as? [String: Any] { result[key] = remoteObject(remote) }
            }
            return result
        }
        return response
    }

    private func evaluationParameters(_ parameters: [String: Any], additional: [String]) throws -> [String: Any] {
        var result = pick(parameters, additional + ["returnByValue", "generatePreview"])
        if parameters["silent"] != nil {
            result["doNotPauseOnExceptionsAndMuteConsole"] = try boolean("silent", in: parameters)
        }
        if parameters["userGesture"] != nil {
            result["emulateUserGesture"] = try boolean("userGesture", in: parameters)
        }
        return result
    }

    private func validateExecutionConstraints(_ parameters: [String: Any]) throws {
        _ = try boolean("replMode", in: parameters)
        for name in ["throwOnSideEffect", "disableBreaks"] {
            if try boolean(name, in: parameters) {
                throw BrowserChromeDebuggerProtocolError.unsupportedParameter(name)
            }
        }
        for name in ["uniqueContextId", "serializationOptions"] where parameters[name] != nil {
            throw BrowserChromeDebuggerProtocolError.unsupportedParameter(name)
        }
        if let timeout = parameters["timeout"] {
            guard let number = timeout as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                number.doubleValue.isFinite, number.doubleValue >= 0
            else { throw BrowserChromeDebuggerProtocolError.invalidParameter("timeout") }
        }
        if parameters["allowUnsafeEvalBlockedByCSP"] != nil,
            try !boolean("allowUnsafeEvalBlockedByCSP", in: parameters)
        {
            throw BrowserChromeDebuggerProtocolError.unsupportedParameter("allowUnsafeEvalBlockedByCSP")
        }
    }

    private func evaluationResult(_ response: [String: Any]) throws -> [String: Any] {
        guard let value = response["result"] as? [String: Any] else {
            throw BrowserChromeDebuggerProtocolError.invalidResult
        }
        let remote = remoteObject(value)
        var result: [String: Any] = ["result": remote]
        if response["wasThrown"] as? Bool == true {
            exceptionSequence += 1
            result["exceptionDetails"] = [
                "exceptionId": exceptionSequence, "text": "Uncaught", "exception": remote,
                // WebKit's evaluation reply has no source-position fields.
                "lineNumber": 0, "columnNumber": 0,
            ]
        }
        return result
    }

    private func remoteObject(_ value: [String: Any]) -> [String: Any] {
        BrowserChromeDebuggerValues.remoteObject(value)
    }

    private func validateCallArguments(_ parameters: [String: Any]) throws {
        guard let value = parameters["arguments"] else { return }
        guard let arguments = value as? [[String: Any]] else {
            throw BrowserChromeDebuggerProtocolError.invalidParameter("arguments")
        }
        for argument in arguments {
            if argument["unserializableValue"] != nil {
                throw BrowserChromeDebuggerProtocolError.unsupportedParameter("arguments.unserializableValue")
            }
            if argument["objectId"] != nil, argument["value"] != nil {
                throw BrowserChromeDebuggerProtocolError.invalidParameter("arguments")
            }
        }
    }

    private func pick(_ source: [String: Any], _ names: [String]) -> [String: Any] {
        BrowserChromeDebuggerValues.pick(source, names)
    }

    private func boolean(_ name: String, in parameters: [String: Any]) throws -> Bool {
        try BrowserChromeDebuggerValues.boolean(name, in: parameters)
    }
}
