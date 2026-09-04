import Foundation

/// Native identities are resolved once from the caller's verified extension
/// context. Neither tab indexes nor page titles confer debugger authority.
struct BrowserExtensionDebuggerTarget: Equatable, Hashable, Sendable {
    let spaceID: SpaceID
    let tabID: TabID
}

struct BrowserExtensionDebuggerCommand: Sendable {
    let method: String
    let parameters: Data
}

struct BrowserExtensionDebuggerSession: Identifiable, Equatable, Sendable {
    enum Phase: Sendable { case attaching, attached }
    let id: UUID
    let target: BrowserExtensionDebuggerTarget
    let clientID: BrowserExtensionServiceClientID
    let displayName: String
    let phase: Phase
}

struct BrowserExtensionDebuggerEvent: Equatable, Sendable {
    enum DetachReason: String, Sendable {
        case targetClosed = "target_closed"
        case canceledByUser = "canceled_by_user"
    }
    enum Kind: Equatable, Sendable {
        case protocolMessage(method: String, parameters: Data)
        case detached(DetachReason)
    }
    let target: BrowserExtensionDebuggerTarget
    let kind: Kind
}

enum BrowserExtensionDebuggerError: Error, Equatable, LocalizedError {
    case accessDenied
    case notAttached
    case alreadyAttached
    case detachedWhileHandling
    case unsupportedVersion(String)
    case invalidRequest
    /// A Chrome DevTools Protocol method Crest does not implement. Carried as
    /// a Domain value so the broker can restate it as the protocol's own
    /// `-32601` text without reaching into a platform type.
    case unsupportedCommand(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied: "Cannot attach to this target."
        case .notAttached: "Debugger is not attached to this target."
        case .alreadyAttached: "Another debugger is already attached to this target."
        case .detachedWhileHandling: "Detached while handling command."
        case .unsupportedVersion(let version): "Requested protocol version is not supported: \(version)."
        case .invalidRequest: "Invalid debugger request."
        case .unsupportedCommand(let method): "'\(method)' wasn't found"
        }
    }
}
