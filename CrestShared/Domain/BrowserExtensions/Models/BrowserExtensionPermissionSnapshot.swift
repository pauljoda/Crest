import Foundation

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
