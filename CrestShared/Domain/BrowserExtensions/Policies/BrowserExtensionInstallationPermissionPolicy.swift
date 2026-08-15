import Foundation

enum BrowserExtensionInstallationPermissionPolicy {
    static func reviewedRequiredAccess(
        permissions: [String],
        hosts: [String]
    ) -> BrowserExtensionPermissionSnapshot {
        BrowserExtensionPermissionSnapshot(
            grantedPermissions: Dictionary(
                uniqueKeysWithValues: Set(permissions).map {
                    ($0, Date.distantFuture)
                }
            ),
            grantedHosts: Dictionary(
                uniqueKeysWithValues: Set(hosts).map {
                    ($0, Date.distantFuture)
                }
            )
        )
    }
}
