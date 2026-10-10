import Foundation

/// Why Crest refused a request: its JSON-RPC code, the reason a tool can
/// match on, which never changes once published, and a message for the
/// person reading the tool's output.
struct BrowserAutomationError: Error {
    // MARK: - Static Variables

    static let parseError = Self(code: -32700, reason: "parse-error", message: "The line is not JSON.")
    static let invalidRequest = Self(
        code: -32600, reason: "invalid-request", message: "The line is not a JSON-RPC 2.0 request.")
    static let helloRequired = Self(
        code: -32002, reason: "hello-required", message: "Send “hello” before any other request.")
    static let notApproved = Self(
        code: -32003, reason: "not-approved", message: "The person has not allowed this tool in Crest.")
    static let declined = Self(
        code: -32003, reason: "declined", message: "The person did not allow this tool to control Crest.")
    static let automationOff = Self(
        code: -32004, reason: "automation-off", message: "Automation is turned off in Crest’s settings.")
    static let unsupportedAddress = Self(
        code: -32602, reason: "unsupported-address", message: "Tools may open only http and https addresses.")
    static let noWindow = Self(
        code: -32013, reason: "no-window",
        message: "No Crest window shows this Space. Open one in Crest, then ask again.")

    // MARK: - Variables

    let code: Int
    let reason: String
    let message: String

    // MARK: - Actions - Errors

    static func methodNotFound(_ method: String) -> Self {
        Self(code: -32601, reason: "method-not-found", message: "Crest has no method “\(method)”.")
    }

    static func invalidParams(_ message: String) -> Self {
        Self(code: -32602, reason: "invalid-params", message: message)
    }

    static func unsupportedProtocol(_ supported: Int) -> Self {
        Self(code: -32001, reason: "unsupported-protocol", message: "This Crest speaks protocol version \(supported).")
    }

    static func spaceUnavailable(_ id: UUID) -> Self {
        Self(
            code: -32010, reason: "space-unavailable",
            message: "Space \(id.uuidString) is not one the person allows tools to reach.")
    }

    static func spaceLocked(_ name: String) -> Self {
        Self(code: -32011, reason: "space-locked", message: "The “\(name)” Space is locked. Unlock it in Crest first.")
    }

    static func tabUnavailable(_ id: UUID) -> Self {
        Self(
            code: -32012, reason: "tab-unavailable", message: "Tab \(id.uuidString) is not in a Space tools may reach.")
    }

    static func refused(_ message: String) -> Self {
        Self(code: -32020, reason: "refused", message: message)
    }
}
