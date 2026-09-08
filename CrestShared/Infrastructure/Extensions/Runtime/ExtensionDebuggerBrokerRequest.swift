import Foundation

/// Chrome's own `chrome.debugger` failure text, reproduced exactly.
///
/// Extensions branch on these strings — the ChatGPT and Claude packages both
/// match `already attached` and `not attached` to decide whether to retry — so
/// paraphrasing them is a compatibility bug, not a wording choice. The tab id
/// interpolated here is the one the caller's own JavaScript resolved and sent
/// back for display; it confers no authority and is never used to address a
/// tab. See `BrowserExtensionDebuggerBrokerRequest`.
enum BrowserExtensionDebuggerBrokerError: LocalizedError, Equatable {
    case invalidRequest
    case invalidTarget
    case noTarget(Int)
    case alreadyAttached(Int)
    case notAttached(Int)
    case restricted
    case unsupportedVersion(String)
    case detachedWhileHandling
    /// A Chrome DevTools Protocol method Crest does not implement. Chrome
    /// forwards the protocol's own `-32601` message unchanged.
    case unsupportedCommand(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest: "The extension supplied an invalid debugger request."
        case .invalidTarget: "Either tab id or extension id must be specified."
        case .noTarget(let tabID): "No tab with given id \(tabID)."
        case .alreadyAttached(let tabID): "Another debugger is already attached to the tab with id: \(tabID)."
        case .notAttached(let tabID): "Debugger is not attached to the tab with id: \(tabID)."
        case .restricted: "Cannot attach to this target."
        case .unsupportedVersion(let version): "Requested protocol version is not supported: \(version)."
        case .detachedWhileHandling: "Detached while handling command."
        case .unsupportedCommand(let method): "'\(method)' wasn't found"
        }
    }
}

/// The wire request behind `chrome.debugger`.
///
/// A tab is named once, at attach, by the primary session index and URL the
/// caller's JavaScript resolved from a native `tabs.get`. Crest verifies that
/// pair against live session state, binds the resulting `TabID` to a minted
/// session token, and every later command addresses the token. Reordering,
/// replacing, or navigating tabs therefore cannot redirect a live debugger
/// session, and a token cannot be guessed into existence: the broker only
/// honours tokens it minted for that client.
///
/// `tabID` rides along for one purpose — reproducing Chrome's error text — and
/// is never consulted when resolving a target.
struct BrowserExtensionDebuggerBrokerRequest {
    enum Operation: String, CaseIterable {
        case attach = "debugger.attach"
        case detach = "debugger.detach"
        case sendCommand = "debugger.sendCommand"
        case getTargets = "debugger.getTargets"
    }

    let operation: Operation
    let tabIndex: Int?
    let url: String?
    let tabID: Int
    let requiredVersion: String
    let sessionToken: String?
    let method: String?
    let parameters: Data

    init(message: [String: Any]) throws {
        guard let api = message["api"] as? String, let operation = Operation(rawValue: api) else {
            throw BrowserExtensionDebuggerBrokerError.invalidRequest
        }
        self.operation = operation
        tabID = (message["tabId"] as? NSNumber)?.intValue ?? -1
        switch operation {
        case .attach:
            guard let index = (message["tabIndex"] as? NSNumber)?.intValue, index >= 0,
                let version = message["requiredVersion"] as? String
            else {
                throw BrowserExtensionDebuggerBrokerError.invalidRequest
            }
            tabIndex = index
            url = message["url"] as? String
            requiredVersion = version
            sessionToken = nil
            method = nil
            parameters = Data()
        case .detach:
            guard let token = message["sessionToken"] as? String, !token.isEmpty else {
                throw BrowserExtensionDebuggerBrokerError.invalidRequest
            }
            tabIndex = nil
            url = nil
            requiredVersion = ""
            sessionToken = token
            method = nil
            parameters = Data()
        case .sendCommand:
            guard let token = message["sessionToken"] as? String, !token.isEmpty,
                let method = message["method"] as? String, !method.isEmpty
            else {
                throw BrowserExtensionDebuggerBrokerError.invalidRequest
            }
            tabIndex = nil
            url = nil
            requiredVersion = ""
            sessionToken = token
            self.method = method
            let supplied = message["params"] as? [String: Any] ?? [:]
            guard JSONSerialization.isValidJSONObject(supplied),
                let data = try? JSONSerialization.data(withJSONObject: supplied)
            else {
                throw BrowserExtensionDebuggerBrokerError.invalidRequest
            }
            parameters = data
        case .getTargets:
            tabIndex = nil
            url = nil
            requiredVersion = ""
            sessionToken = nil
            method = nil
            parameters = Data()
        }
    }
}

/// One live `token -> tab` binding, plus the identity that owns it.
///
/// The identity is captured when the extension's context loads, not read back
/// from the caller, so a later message cannot claim a different extension.
struct BrowserExtensionDebuggerBinding: Equatable, Sendable {
    let target: BrowserExtensionDebuggerTarget
    let client: BrowserExtensionServiceClientID
    let identity: BrowserExtensionDebuggerIdentity
    /// The tab id the extension's own JavaScript uses. Display only.
    let tabID: Int
}

/// The extension behind a debugger client, as Crest verified it at context load.
struct BrowserExtensionDebuggerIdentity: Equatable, Sendable {
    let extensionID: String
    let spaceID: SpaceID
    let displayName: String
    let baseURL: URL
}
