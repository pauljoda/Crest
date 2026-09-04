import Foundation

/// The value translations every CDP domain shares. Console arguments,
/// evaluation results, and property values all cross the same boundary, so
/// they must not drift into separate per-domain conversions.
enum BrowserChromeDebuggerValues {
    /// WebKit reports non-JSON numbers and big integers through `description`.
    /// Chrome carries them in `unserializableValue`, and a client that reads
    /// `value` must not see a silently coerced number instead.
    static func remoteObject(_ value: [String: Any]) -> [String: Any] {
        var remote = value
        guard let description = value["description"] as? String else { return remote }
        if value["type"] as? String == "number", ["NaN", "Infinity", "-Infinity", "-0"].contains(description) {
            remote["value"] = nil
            remote["unserializableValue"] = description
        }
        if value["type"] as? String == "bigint" {
            remote["value"] = nil
            remote["unserializableValue"] = description.hasSuffix("n") ? description : description + "n"
        }
        return remote
    }

    /// WebKit's `Console.StackTrace` nests through `parentStackTrace`; Chrome
    /// nests through `parent`. Frame fields otherwise match.
    static func stackTrace(_ value: [String: Any]) -> [String: Any] {
        var trace: [String: Any] = [:]
        let frames = value["callFrames"] as? [[String: Any]] ?? []
        trace["callFrames"] = frames.map { frame in
            [
                "functionName": frame["functionName"] as? String ?? "",
                "scriptId": scriptIdentifier(frame["scriptId"]),
                "url": frame["url"] as? String ?? "",
                "lineNumber": zeroBasedPosition(frame["lineNumber"]),
                "columnNumber": zeroBasedPosition(frame["columnNumber"]),
            ]
        }
        if let parent = value["parentStackTrace"] as? [String: Any] {
            trace["parent"] = stackTrace(parent)
        }
        return trace
    }

    /// WebKit reports source positions as one-based; Chrome's are zero-based.
    /// A missing position becomes zero rather than a negative line number.
    static func zeroBasedPosition(_ value: Any?) -> Int {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue.isFinite
        else { return 0 }
        return max(0, number.intValue - 1)
    }

    /// Chrome types `scriptId` as a string. WebKit already does, but resources
    /// without a parsed script omit it entirely.
    static func scriptIdentifier(_ value: Any?) -> String {
        if let text = value as? String { return text }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.stringValue
        }
        return ""
    }

    /// WebKit encodes its remote object identity as JSON carrying the injected
    /// script that owns it. That script identity is the execution context ID
    /// Chrome reports, which is the only in-band context a console message has.
    static func executionContext(inObjectID objectID: Any?) -> Int? {
        guard let text = objectID as? String, let data = text.data(using: .utf8),
            let identity = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let injected = identity["injectedScriptId"] as? NSNumber,
            CFGetTypeID(injected) != CFBooleanGetTypeID()
        else { return nil }
        return injected.intValue
    }

    static func pick(_ source: [String: Any], _ names: [String]) -> [String: Any] {
        source.filter { names.contains($0.key) }
    }

    static func boolean(_ name: String, in parameters: [String: Any]) throws -> Bool {
        guard let value = parameters[name] else { return false }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw BrowserChromeDebuggerProtocolError.invalidParameter(name)
        }
        return number.boolValue
    }

    static func number(_ value: Any?, name: String) throws -> Double {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue.isFinite
        else { throw BrowserChromeDebuggerProtocolError.invalidParameter(name) }
        return number.doubleValue
    }

    static func integer(_ value: Any?, name: String) throws -> Int {
        let value = try number(value, name: name)
        guard value.rounded() == value, value >= Double(Int32.min), value <= Double(Int32.max) else {
            throw BrowserChromeDebuggerProtocolError.invalidParameter(name)
        }
        return Int(value)
    }
}
