import Foundation
import WebKit

@MainActor
final class BrowserExtensionPermissionController {
    private let persistence: BrowserExtensionPersistenceController

    init(persistence: BrowserExtensionPersistenceController) {
        self.persistence = persistence
    }

    func permissionDecision(
        for permission: String,
        extensionID: String,
        in spaceID: SpaceID
    ) -> BrowserExtensionAccessDecision {
        guard
            let installation = persistence.installation(
                extensionID: extensionID,
                in: spaceID
            )
        else {
            return .ask
        }
        if installation.permissionSnapshot
            .grantedPermissions[permission] != nil
        {
            return .allow
        }
        if installation.permissionSnapshot
            .deniedPermissions[permission] != nil
        {
            return .block
        }
        return .ask
    }

    func hostDecision(
        for hostPattern: String,
        extensionID: String,
        in spaceID: SpaceID
    ) -> BrowserExtensionAccessDecision {
        guard
            let installation = persistence.installation(
                extensionID: extensionID,
                in: spaceID
            )
        else {
            return .ask
        }
        if installation.permissionSnapshot
            .grantedHosts[hostPattern] != nil
        {
            return .allow
        }
        if installation.permissionSnapshot
            .deniedHosts[hostPattern] != nil
        {
            return .block
        }
        return .ask
    }

    func setPermissionDecision(
        _ decision: BrowserExtensionAccessDecision,
        for permission: String,
        extensionID: String,
        in spaceID: SpaceID,
        context: WKWebExtensionContext?,
        nativeMessagingCapability: BrowserExtensionNativeMessagingCapability
    ) {
        guard let context else {
            updateStoredPermission(
                decision,
                permission: permission,
                extensionID: extensionID,
                spaceID: spaceID,
                nativeMessagingCapability: nativeMessagingCapability
            )
            return
        }
        context.setPermissionStatus(
            webKitStatus(for: decision),
            for: WKWebExtension.Permission(rawValue: permission)
        )
        persistPermissionState(
            context: context,
            extensionID: extensionID,
            in: spaceID
        )
    }

    func setHostDecision(
        _ decision: BrowserExtensionAccessDecision,
        for hostPattern: String,
        extensionID: String,
        in spaceID: SpaceID,
        context: WKWebExtensionContext?,
        nativeMessagingCapability: BrowserExtensionNativeMessagingCapability
    ) {
        guard
            let pattern = try? WKWebExtension.MatchPattern(
                string: hostPattern
            )
        else {
            return
        }
        guard let context else {
            updateStoredHost(
                decision,
                hostPattern: hostPattern,
                extensionID: extensionID,
                spaceID: spaceID,
                nativeMessagingCapability: nativeMessagingCapability
            )
            return
        }
        context.setPermissionStatus(
            webKitStatus(for: decision),
            for: pattern
        )
        persistPermissionState(
            context: context,
            extensionID: extensionID,
            in: spaceID
        )
    }

    func persistPermissionState(
        context: WKWebExtensionContext,
        extensionID: String,
        in spaceID: SpaceID,
        excluding excludedPermissions: Set<String> = []
    ) {
        let snapshot = snapshot(
            for: context,
            excluding: excludedPermissions
        )
        persistence.updatePermissionSnapshot(
            snapshot,
            extensionID: extensionID,
            in: spaceID
        )
        guard
            let installation = persistence.installation(
                extensionID: extensionID,
                in: spaceID
            )
        else {
            return
        }
        persistence.updateSummary(
            persistence.summary(
                for: context,
                installation: installation,
                permissionSnapshot: snapshot,
                excluding: excludedPermissions
            ),
            in: spaceID
        )
    }

    /// Rebuilds a context's permission state from a stored snapshot. Any host
    /// pattern WebKit's parser now rejects is reported instead of dropped in
    /// silence, because a silently discarded grant looks to the person like
    /// Crest revoked website access on its own.
    func apply(
        _ snapshot: BrowserExtensionPermissionSnapshot,
        to context: WKWebExtensionContext
    ) -> BrowserExtensionPermissionRestoreError? {
        context.grantedPermissions = permissionDictionary(
            snapshot.grantedPermissions
        )
        context.deniedPermissions = permissionDictionary(
            snapshot.deniedPermissions
        )
        var droppedHostPatterns: [String] = []
        context.grantedPermissionMatchPatterns = hostDictionary(
            snapshot.grantedHosts,
            dropped: &droppedHostPatterns
        )
        context.deniedPermissionMatchPatterns = hostDictionary(
            snapshot.deniedHosts,
            dropped: &droppedHostPatterns
        )
        context.hasRequestedOptionalAccessToAllHosts =
            snapshot.hasRequestedOptionalAccessToAllHosts
        guard !droppedHostPatterns.isEmpty else { return nil }
        return BrowserExtensionPermissionRestoreError(
            droppedHostPatterns: droppedHostPatterns
        )
    }

    func snapshot(
        for context: WKWebExtensionContext,
        excluding excludedPermissions: Set<String> = []
    ) -> BrowserExtensionPermissionSnapshot {
        BrowserExtensionPermissionSnapshot(
            grantedPermissions: Dictionary(
                uniqueKeysWithValues: context.grantedPermissions.map {
                    ($0.key.rawValue, $0.value)
                }.filter { !excludedPermissions.contains($0.0) }
            ),
            deniedPermissions: Dictionary(
                uniqueKeysWithValues: context.deniedPermissions.map {
                    ($0.key.rawValue, $0.value)
                }.filter { !excludedPermissions.contains($0.0) }
            ),
            grantedHosts: Dictionary(
                uniqueKeysWithValues:
                    context.grantedPermissionMatchPatterns.map {
                        ($0.key.string, $0.value)
                    }
            ),
            deniedHosts: Dictionary(
                uniqueKeysWithValues:
                    context.deniedPermissionMatchPatterns.map {
                        ($0.key.string, $0.value)
                    }
            ),
            hasRequestedOptionalAccessToAllHosts:
                context.hasRequestedOptionalAccessToAllHosts
        )
    }

    private func permissionDictionary(
        _ values: [String: Date]
    ) -> [WKWebExtension.Permission: Date] {
        Dictionary(
            uniqueKeysWithValues: values.map {
                (
                    WKWebExtension.Permission(rawValue: $0.key),
                    $0.value
                )
            }
        )
    }

    private func hostDictionary(
        _ values: [String: Date],
        dropped: inout [String]
    ) -> [WKWebExtension.MatchPattern: Date] {
        var result: [WKWebExtension.MatchPattern: Date] = [:]
        for (encodedPattern, expiration) in values {
            guard
                let pattern = try? WKWebExtension.MatchPattern(
                    string: encodedPattern
                )
            else {
                dropped.append(encodedPattern)
                continue
            }
            result[pattern] = expiration
        }
        return result
    }

    private func webKitStatus(
        for decision: BrowserExtensionAccessDecision
    ) -> WKWebExtensionContext.PermissionStatus {
        switch decision {
        case .ask:
            .unknown
        case .allow:
            .grantedExplicitly
        case .block:
            .deniedExplicitly
        }
    }

    private func updateStoredPermission(
        _ decision: BrowserExtensionAccessDecision,
        permission: String,
        extensionID: String,
        spaceID: SpaceID,
        nativeMessagingCapability: BrowserExtensionNativeMessagingCapability
    ) {
        guard
            let installation = persistence.installation(
                extensionID: extensionID,
                in: spaceID
            )
        else {
            return
        }
        var snapshot = installation.permissionSnapshot
        snapshot.grantedPermissions.removeValue(forKey: permission)
        snapshot.deniedPermissions.removeValue(forKey: permission)
        switch decision {
        case .ask:
            break
        case .allow:
            snapshot.grantedPermissions[permission] = .distantFuture
        case .block:
            snapshot.deniedPermissions[permission] = .distantFuture
        }
        updateStoredSnapshot(
            snapshot,
            extensionID: extensionID,
            spaceID: spaceID,
            nativeMessagingCapability: nativeMessagingCapability
        )
    }

    private func updateStoredHost(
        _ decision: BrowserExtensionAccessDecision,
        hostPattern: String,
        extensionID: String,
        spaceID: SpaceID,
        nativeMessagingCapability: BrowserExtensionNativeMessagingCapability
    ) {
        guard
            let installation = persistence.installation(
                extensionID: extensionID,
                in: spaceID
            )
        else {
            return
        }
        var snapshot = installation.permissionSnapshot
        snapshot.grantedHosts.removeValue(forKey: hostPattern)
        snapshot.deniedHosts.removeValue(forKey: hostPattern)
        switch decision {
        case .ask:
            break
        case .allow:
            snapshot.grantedHosts[hostPattern] = .distantFuture
        case .block:
            snapshot.deniedHosts[hostPattern] = .distantFuture
        }
        updateStoredSnapshot(
            snapshot,
            extensionID: extensionID,
            spaceID: spaceID,
            nativeMessagingCapability: nativeMessagingCapability
        )
    }

    private func updateStoredSnapshot(
        _ snapshot: BrowserExtensionPermissionSnapshot,
        extensionID: String,
        spaceID: SpaceID,
        nativeMessagingCapability: BrowserExtensionNativeMessagingCapability
    ) {
        persistence.updatePermissionSnapshot(
            snapshot,
            extensionID: extensionID,
            in: spaceID
        )
        guard
            let updated = persistence.installation(
                extensionID: extensionID,
                in: spaceID
            )
        else {
            return
        }
        persistence.updateSummary(
            persistence.summary(
                for: updated,
                nativeMessagingCapability: nativeMessagingCapability
            ),
            in: spaceID
        )
    }
}
