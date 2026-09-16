import Foundation

enum BrowserExtensionInstallationPermissionPolicy {
    struct Review: Equatable, Sendable {
        var previousSnapshot: BrowserExtensionPermissionSnapshot?
        var additionalSpaceIDs: Set<SpaceID> = []
        var permissions: [String: Bool] = [:]
        var hosts: [String: Bool] = [:]

        func allowsPermission(_ permission: String) -> Bool {
            permissions[permission] ?? previousSnapshot.map {
                BrowserExtensionManagedPermissionPolicy.decision(for: permission, in: $0) == .allow
            } ?? true
        }

        func allowsHost(_ host: String) -> Bool {
            hosts[host] ?? previousSnapshot.map {
                ($0.deniedHosts[host] ?? .distantPast) <= .now
                    && ($0.grantedHosts[host] ?? .distantPast) > .now
            } ?? true
        }
    }

    static func reviewedRequiredAccess(
        permissions: [String],
        hosts: [String],
        previous: BrowserExtensionPermissionSnapshot? = nil,
        review: Review = .init()
    ) -> BrowserExtensionPermissionSnapshot {
        var snapshot =
            previous
            ?? BrowserExtensionPermissionSnapshot(
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
        for permission in Set(permissions) {
            guard let allowed = review.permissions[permission] else { continue }
            snapshot.grantedPermissions[permission] = allowed ? .distantFuture : nil
            snapshot.deniedPermissions[permission] = allowed ? nil : .distantFuture
        }
        for host in Set(hosts) {
            guard let allowed = review.hosts[host] else { continue }
            snapshot.grantedHosts[host] = allowed ? .distantFuture : nil
            snapshot.deniedHosts[host] = allowed ? nil : .distantFuture
        }
        return snapshot
    }
}
