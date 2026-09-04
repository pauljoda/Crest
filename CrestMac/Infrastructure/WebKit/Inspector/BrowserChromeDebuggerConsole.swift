import Foundation

/// Publishes CDP `Runtime.consoleAPICalled` and `Runtime.exceptionThrown` from
/// WebKit's `Console` domain. WebKit routes both through one `messageAdded`
/// channel, so the source and level decide which Chrome event a message is.
///
/// Chrome scopes console output to an execution context; a WebKit console
/// message carries none. The context is recovered from the injected script that
/// owns an argument's remote object, and otherwise from a probe of the page's
/// own context, so a client filtering by context is never handed a guess.
@MainActor
final class BrowserChromeDebuggerConsole {
    var onEvent: ((String, [String: Any]) -> Void)?

    private let connection: BrowserWebInspectorProtocolConnection
    private var enabledAttachment: UUID?
    private var probedContext: (attachment: UUID, id: Int)?
    private var exceptionSequence = 0
    /// The most recent console-API event, replayed when WebKit coalesces an
    /// identical repeat instead of sending another `messageAdded`.
    private var lastConsoleCall: [String: Any]?

    private var isEnabled: Bool {
        enabledAttachment != nil && enabledAttachment == connection.attachmentIdentifier
    }

    init(connection: BrowserWebInspectorProtocolConnection) {
        self.connection = connection
    }

    /// Enabled alongside `Runtime.enable`: Chrome delivers console output on
    /// the Runtime domain, so an agent that never names `Console` still expects
    /// `consoleAPICalled`.
    func enable() async throws {
        guard let attachment = connection.attachmentIdentifier else {
            throw BrowserWebInspectorProtocolError.notConnected
        }
        if enabledAttachment == attachment { return }
        _ = try await connection.sendCommand("Console.enable")
        enabledAttachment = attachment
    }

    /// Stops forwarding without disabling WebKit's own domain. Inspector
    /// bootstrapped `Console` for itself, and taking it away would silence the
    /// frontend this transport is borrowing.
    func disable() {
        enabledAttachment = nil
        lastConsoleCall = nil
    }

    func receive(_ method: String, parameters: [String: Any]) {
        guard isEnabled else { return }
        switch method {
        case "Console.messageAdded":
            guard let message = parameters["message"] as? [String: Any] else { return }
            publish(message)
        case "Console.messageRepeatCountUpdated":
            // WebKit coalesces identical consecutive messages into a repeat
            // count. Chrome emits one event per call, so replay the message.
            guard var call = lastConsoleCall else { return }
            call["timestamp"] = milliseconds(parameters["timestamp"])
            onEvent?("Runtime.consoleAPICalled", call)
        case "Console.messagesCleared":
            lastConsoleCall = nil
        default:
            return
        }
    }

    private func publish(_ message: [String: Any]) {
        let source = message["source"] as? String
        let level = message["level"] as? String ?? "log"
        let arguments = (message["parameters"] as? [[String: Any]] ?? []).map(
            BrowserChromeDebuggerValues.remoteObject)
        if source == "javascript", level == "error" {
            onEvent?("Runtime.exceptionThrown", exception(message, arguments: arguments))
            return
        }
        guard source == "console-api" else { return }
        var call: [String: Any] = [
            "type": consoleType(message["type"] as? String, level: level),
            "args": arguments.isEmpty ? [textArgument(message)] : arguments,
            "executionContextId": executionContext(for: arguments),
            "timestamp": milliseconds(message["timestamp"]),
        ]
        if let trace = message["stackTrace"] as? [String: Any] {
            call["stackTrace"] = BrowserChromeDebuggerValues.stackTrace(trace)
        }
        lastConsoleCall = call
        onEvent?("Runtime.consoleAPICalled", call)
    }

    private func exception(_ message: [String: Any], arguments: [[String: Any]]) -> [String: Any] {
        exceptionSequence += 1
        var details: [String: Any] = [
            "exceptionId": exceptionSequence,
            "text": message["text"] as? String ?? "Uncaught",
            "lineNumber": BrowserChromeDebuggerValues.zeroBasedPosition(message["line"]),
            "columnNumber": BrowserChromeDebuggerValues.zeroBasedPosition(message["column"]),
        ]
        if let url = message["url"] as? String { details["url"] = url }
        if let trace = message["stackTrace"] as? [String: Any] {
            details["stackTrace"] = BrowserChromeDebuggerValues.stackTrace(trace)
        }
        // WebKit reports the thrown value as the message's first parameter.
        if let thrown = arguments.first {
            details["exception"] = thrown
            details["executionContextId"] = executionContext(for: arguments)
        }
        return ["timestamp": milliseconds(message["timestamp"]), "exceptionDetails": details]
    }

    /// WebKit reports the console method in `type` and the severity in `level`.
    /// Chrome folds both into one `type`, so an ordinary `log` defers to its
    /// level and every other console method names itself.
    private func consoleType(_ type: String?, level: String) -> String {
        switch type {
        case nil, "log":
            return ["log", "info", "warning", "error", "debug"].contains(level) ? level : "log"
        case "timing":
            return "timeEnd"
        case "image":
            // Chrome has no image console type; the message still reads as output.
            return "log"
        case let value?:
            return value
        }
    }

    /// A console message that WebKit did not expand into remote objects still
    /// has its rendered text, which is what the message meant.
    private func textArgument(_ message: [String: Any]) -> [String: Any] {
        ["type": "string", "value": message["text"] as? String ?? ""]
    }

    private func executionContext(for arguments: [[String: Any]]) -> Int {
        for argument in arguments {
            if let id = BrowserChromeDebuggerValues.executionContext(inObjectID: argument["objectId"]) {
                return id
            }
        }
        if let probedContext, probedContext.attachment == connection.attachmentIdentifier {
            return probedContext.id
        }
        probeExecutionContext()
        return probedContext?.id ?? 1
    }

    /// Asks the page for a remote object once per attachment purely to read the
    /// injected-script identity back off it, then releases it. Nothing observable
    /// is left in the page: the expression allocates one empty object.
    private func probeExecutionContext() {
        guard let attachment = connection.attachmentIdentifier else { return }
        Task { @MainActor [weak self] in
            guard let self, self.probedContext?.attachment != attachment else { return }
            let response = try? await self.connection.sendCommand(
                "Runtime.evaluate",
                parameters: ["expression": "({})", "doNotPauseOnExceptionsAndMuteConsole": true])
            guard let object = response?["result"] as? [String: Any], let objectID = object["objectId"] as? String
            else { return }
            defer {
                Task { @MainActor [weak self] in
                    _ = try? await self?.connection.sendCommand(
                        "Runtime.releaseObject", parameters: ["objectId": objectID])
                }
            }
            guard self.connection.attachmentIdentifier == attachment,
                let id = BrowserChromeDebuggerValues.executionContext(inObjectID: objectID)
            else { return }
            self.probedContext = (attachment, id)
        }
    }

    /// WebKit timestamps console messages in milliseconds since the epoch,
    /// which is already Chrome's `Runtime.Timestamp` unit.
    private func milliseconds(_ value: Any?) -> Double {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue.isFinite, number.doubleValue > 0
        else { return Date().timeIntervalSince1970 * 1000 }
        return number.doubleValue
    }
}
