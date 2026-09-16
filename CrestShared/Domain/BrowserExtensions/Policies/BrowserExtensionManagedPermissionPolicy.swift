import Foundation

/// Permissions whose user decisions Crest owns because WebKit does not retain
/// them. Declaring a permission is not a grant, and this does not publish an API.
enum BrowserExtensionManagedPermissionPolicy {
    static let names: Set<String> = [
        "debugger", "clipboardRead", "identity", "idle", "offscreen", "sidePanel", "tabGroups", "sidebarAction",
    ]

    static func requestedPermissions(
        native: [String], manifest: [String: Any], excluding excluded: Set<String> = []
    ) -> [String] {
        let declared = Set(manifest["permissions"] as? [String] ?? []).intersection(names)
        let manifestCapabilities = BrowserExtensionAPICompatibilityMatrix.capabilityBrokerGrantedCapabilities(
            manifest: manifest)
        return Set(native).union(declared).union(manifestCapabilities).subtracting(excluded).sorted()
    }

    static func managedSnapshot(from snapshot: BrowserExtensionPermissionSnapshot) -> BrowserExtensionPermissionSnapshot
    {
        .init(
            grantedPermissions: snapshot.grantedPermissions.filter { names.contains($0.key) },
            deniedPermissions: snapshot.deniedPermissions.filter { names.contains($0.key) })
    }

    static func merge(
        native: BrowserExtensionPermissionSnapshot, managed: BrowserExtensionPermissionSnapshot,
        excluding excluded: Set<String> = []
    ) -> BrowserExtensionPermissionSnapshot {
        var result = native
        for permission in names {
            result.grantedPermissions[permission] =
                excluded.contains(permission) ? nil : managed.grantedPermissions[permission]
            result.deniedPermissions[permission] =
                excluded.contains(permission) ? nil : managed.deniedPermissions[permission]
        }
        return result
    }

    static func decision(
        for permission: String, in snapshot: BrowserExtensionPermissionSnapshot, now: Date = .now
    ) -> BrowserExtensionAccessDecision {
        if let expiration = snapshot.deniedPermissions[permission], expiration > now { return .block }
        if let expiration = snapshot.grantedPermissions[permission], expiration > now { return .allow }
        return .ask
    }

    static func effectivePermissions(
        in snapshot: BrowserExtensionPermissionSnapshot, now: Date = .now
    ) -> Set<String> {
        var permissions = Set(
            snapshot.grantedPermissions.keys.filter {
                decision(for: $0, in: snapshot, now: now) == .allow
            })
        // Firefox's menus grant authorizes the shared context-menu broker,
        // but never overrides an explicit denial of that capability.
        if permissions.contains("menus"), decision(for: "contextMenus", in: snapshot, now: now) != .block {
            permissions.insert("contextMenus")
        }
        return permissions
    }
}
