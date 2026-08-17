import Foundation

enum BrowserExtensionAccessDecision:
    String,
    CaseIterable,
    Hashable,
    Identifiable
{
    case ask
    case allow
    case block

    var id: String { rawValue }
}

/// Website-access grants that could not be rebuilt from a stored permission
/// snapshot. Restoring stays non-fatal, so this is reported against the
/// extension rather than thrown.
struct BrowserExtensionPermissionRestoreError: Error, Equatable {
    let droppedHostPatterns: [String]
}

struct BrowserExtensionPermissionSnapshot: Codable, Equatable, Sendable {
    var grantedPermissions: [String: Date]
    var deniedPermissions: [String: Date]
    var grantedHosts: [String: Date]
    var deniedHosts: [String: Date]
    var hasRequestedOptionalAccessToAllHosts: Bool

    init(
        grantedPermissions: [String: Date] = [:],
        deniedPermissions: [String: Date] = [:],
        grantedHosts: [String: Date] = [:],
        deniedHosts: [String: Date] = [:],
        hasRequestedOptionalAccessToAllHosts: Bool = false
    ) {
        self.grantedPermissions = grantedPermissions
        self.deniedPermissions = deniedPermissions
        self.grantedHosts = grantedHosts
        self.deniedHosts = deniedHosts
        self.hasRequestedOptionalAccessToAllHosts =
            hasRequestedOptionalAccessToAllHosts
    }

    static let empty = BrowserExtensionPermissionSnapshot()
}
