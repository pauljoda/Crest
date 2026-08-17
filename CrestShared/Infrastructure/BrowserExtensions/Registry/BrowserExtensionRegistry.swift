import Foundation
import Observation

@Observable
@MainActor
final class BrowserExtensionRegistry {
    private struct InstallationKey: Hashable {
        let spaceID: SpaceID
        let extensionID: String
    }

    private static let maximumInstallationCount = 256
    private static let maximumIdentifierLength = 256
    private static let maximumPackageNameLength = 255
    private static let maximumMetadataItemCount = 256
    private static let maximumMetadataLength = 2_048
    private static let maximumErrorCount = 20
    private static let maximumVersionLength = 64

    private(set) var installations: [BrowserExtensionInstallation]

    @ObservationIgnored private let persistence: any BrowserExtensionRegistryPersisting

    init(
        persistence: any BrowserExtensionRegistryPersisting =
            InMemoryBrowserExtensionRegistryPersistence()
    ) {
        self.persistence = persistence
        let loaded = persistence.load()
        let repaired = Self.repaired(loaded)
        installations = repaired
        if repaired != loaded {
            persistence.save(repaired)
        }
    }

    static func production() -> BrowserExtensionRegistry {
        BrowserExtensionRegistry(
            persistence: UserDefaultsBrowserExtensionRegistryPersistence()
        )
    }

    func installations(
        in spaceID: SpaceID
    ) -> [BrowserExtensionInstallation] {
        installations
            .filter { $0.spaceID == spaceID }
            .sorted {
                $0.displayName.localizedStandardCompare($1.displayName)
                    == .orderedAscending
            }
    }

    func installation(
        extensionID: String,
        in spaceID: SpaceID
    ) -> BrowserExtensionInstallation? {
        installations.first {
            $0.spaceID == spaceID && $0.id == extensionID
        }
    }

    @discardableResult
    func upsert(_ installation: BrowserExtensionInstallation) -> Bool {
        guard let normalized = Self.normalized(installation) else {
            return false
        }
        installations.removeAll {
            $0.spaceID == normalized.spaceID && $0.id == normalized.id
        }
        installations.append(normalized)
        installations = Self.repaired(installations)
        persist()
        return true
    }

    func setEnabled(
        _ enabled: Bool,
        extensionID: String,
        in spaceID: SpaceID,
        at date: Date = .now
    ) {
        mutate(extensionID: extensionID, in: spaceID) {
            $0.isEnabled = enabled
            $0.modifiedAt = date
        }
    }

    func setPinned(
        _ pinned: Bool,
        extensionID: String,
        in spaceID: SpaceID,
        at date: Date = .now
    ) {
        mutate(extensionID: extensionID, in: spaceID) {
            $0.isPinned = pinned
            $0.modifiedAt = date
        }
    }

    func setCommandShortcutOverride(
        _ override: BrowserExtensionCommandShortcutOverride,
        commandID: String,
        extensionID: String,
        in spaceID: SpaceID,
        at date: Date = .now
    ) {
        mutate(extensionID: extensionID, in: spaceID) {
            var overrides = $0.commandShortcutOverrides ?? [:]
            overrides[commandID] = override
            $0.commandShortcutOverrides = overrides
            $0.modifiedAt = date
        }
    }

    func resetCommandShortcutOverride(
        commandID: String,
        extensionID: String,
        in spaceID: SpaceID,
        at date: Date = .now
    ) {
        mutate(extensionID: extensionID, in: spaceID) {
            var overrides = $0.commandShortcutOverrides ?? [:]
            overrides.removeValue(forKey: commandID)
            $0.commandShortcutOverrides = overrides.isEmpty ? nil : overrides
            $0.modifiedAt = date
        }
    }

    func updatePermissionSnapshot(
        _ snapshot: BrowserExtensionPermissionSnapshot,
        extensionID: String,
        in spaceID: SpaceID,
        at date: Date = .now
    ) {
        mutate(extensionID: extensionID, in: spaceID) {
            $0.permissionSnapshot = snapshot
            $0.modifiedAt = date
        }
    }

    func updateRuntimeSummary(
        displayName: String,
        version: String?,
        requestedPermissions: [String],
        requestedHosts: [String],
        unsupportedAPIs: [String],
        errors: [String],
        extensionID: String,
        in spaceID: SpaceID,
        at date: Date = .now
    ) {
        mutate(extensionID: extensionID, in: spaceID) {
            $0.displayName = displayName
            $0.version = version
            $0.requestedPermissions = requestedPermissions
            $0.requestedHosts = requestedHosts
            $0.unsupportedAPIs = unsupportedAPIs
            $0.errors = errors
            $0.modifiedAt = date
        }
    }

    @discardableResult
    func remove(
        extensionID: String,
        from spaceID: SpaceID
    ) -> BrowserExtensionInstallation? {
        guard
            let index = installations.firstIndex(where: {
                $0.spaceID == spaceID && $0.id == extensionID
            })
        else {
            return nil
        }
        let removed = installations.remove(at: index)
        persist()
        return removed
    }

    func removeAll(in spaceID: SpaceID) {
        let originalCount = installations.count
        installations.removeAll { $0.spaceID == spaceID }
        if installations.count != originalCount {
            persist()
        }
    }

    private func mutate(
        extensionID: String,
        in spaceID: SpaceID,
        mutation: (inout BrowserExtensionInstallation) -> Void
    ) {
        guard
            let index = installations.firstIndex(where: {
                $0.spaceID == spaceID && $0.id == extensionID
            })
        else {
            return
        }
        mutation(&installations[index])
        guard let normalized = Self.normalized(installations[index]) else {
            installations.remove(at: index)
            persist()
            return
        }
        installations[index] = normalized
        persist()
    }

    private func persist() {
        persistence.save(installations)
    }

    private static func repaired(
        _ candidates: [BrowserExtensionInstallation]
    ) -> [BrowserExtensionInstallation] {
        var newestByKey: [InstallationKey: BrowserExtensionInstallation] = [:]
        for candidate in candidates {
            guard let normalized = normalized(candidate) else { continue }
            let key = InstallationKey(
                spaceID: normalized.spaceID,
                extensionID: normalized.id
            )
            if let existing = newestByKey[key],
                existing.modifiedAt >= normalized.modifiedAt
            {
                continue
            }
            newestByKey[key] = normalized
        }
        return newestByKey.values
            .sorted {
                if $0.modifiedAt != $1.modifiedAt {
                    return $0.modifiedAt > $1.modifiedAt
                }
                if $0.spaceID != $1.spaceID {
                    return $0.spaceID.rawValue.uuidString
                        < $1.spaceID.rawValue.uuidString
                }
                return $0.id < $1.id
            }
            .prefix(maximumInstallationCount)
            .map(\.self)
    }

    private static func normalized(
        _ candidate: BrowserExtensionInstallation
    ) -> BrowserExtensionInstallation? {
        guard isSafeIdentifier(candidate.id),
            isSafePackageName(candidate.packageName),
            let displayName = normalizedText(candidate.displayName),
            isSafeSource(candidate.source, extensionID: candidate.id)
        else {
            return nil
        }
        var normalized = candidate
        normalized.displayName = displayName
        normalized.version = candidate.version.flatMap(normalizedText)
        normalized.requestedPermissions = normalizedMetadata(
            candidate.requestedPermissions
        )
        normalized.requestedHosts = normalizedMetadata(
            candidate.requestedHosts
        )
        normalized.unsupportedAPIs = normalizedMetadata(
            candidate.unsupportedAPIs
        )
        normalized.errors = Array(
            normalizedMetadata(candidate.errors)
                .prefix(maximumErrorCount)
        )
        normalized.permissionSnapshot = normalizedSnapshot(
            candidate.permissionSnapshot
        )
        normalized.commandShortcutOverrides = normalizedCommandShortcuts(
            candidate.commandShortcutOverrides
        )
        normalized.sourceDisplayName = candidate.sourceDisplayName
            .flatMap(normalizedText)
        if let iconData = candidate.iconData,
            iconData.count
                <= BrowserExtensionIconPayload.maximumEncodedByteCount
        {
            normalized.iconData = iconData
        } else {
            normalized.iconData = nil
        }
        return normalized
    }

    private static func normalizedCommandShortcuts(
        _ overrides: [String: BrowserExtensionCommandShortcutOverride]?
    ) -> [String: BrowserExtensionCommandShortcutOverride]? {
        guard let overrides else { return nil }
        var result: [String: BrowserExtensionCommandShortcutOverride] = [:]
        for (commandID, override) in overrides.sorted(by: { $0.key < $1.key }) {
            guard result.count < maximumMetadataItemCount,
                let normalizedID = normalizedText(commandID)
            else {
                continue
            }
            switch override {
            case .custom(let shortcut):
                guard shortcut.isValid,
                    BrowserExtensionShortcutPolicy.activationKey(
                        for: shortcut.key
                    ) != nil
                else {
                    continue
                }
            case .unassigned:
                break
            }
            result[normalizedID] = override
        }
        return result.isEmpty ? nil : result
    }

    private static func normalizedSnapshot(
        _ snapshot: BrowserExtensionPermissionSnapshot
    ) -> BrowserExtensionPermissionSnapshot {
        BrowserExtensionPermissionSnapshot(
            grantedPermissions: normalizedDates(
                snapshot.grantedPermissions
            ),
            deniedPermissions: normalizedDates(snapshot.deniedPermissions),
            grantedHosts: normalizedDates(snapshot.grantedHosts),
            deniedHosts: normalizedDates(snapshot.deniedHosts),
            hasRequestedOptionalAccessToAllHosts:
                snapshot.hasRequestedOptionalAccessToAllHosts
        )
    }

    private static func normalizedDates(
        _ values: [String: Date]
    ) -> [String: Date] {
        var result: [String: Date] = [:]
        for (key, date) in values.sorted(by: { $0.key < $1.key }) {
            guard result.count < maximumMetadataItemCount,
                let normalizedKey = normalizedText(key)
            else {
                continue
            }
            result[normalizedKey] = date
        }
        return result
    }

    private static func normalizedMetadata(
        _ values: [String]
    ) -> [String] {
        Array(
            Set(values.compactMap(normalizedText))
                .sorted()
                .prefix(maximumMetadataItemCount)
        )
    }

    private static func normalizedText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty,
            trimmed.utf8.count <= maximumMetadataLength,
            !trimmed.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            })
        else {
            return nil
        }
        return trimmed
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty,
            value.utf8.count <= maximumIdentifierLength
        else {
            return false
        }
        return !value.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
    }

    private static func isSafePackageName(_ value: String) -> Bool {
        guard !value.isEmpty,
            value.utf8.count <= maximumPackageNameLength,
            value != ".",
            value != "..",
            !value.contains("/"),
            !value.contains("\\")
        else {
            return false
        }
        return URL(fileURLWithPath: value).lastPathComponent == value
    }

    private static func isSafeSource(
        _ source: BrowserExtensionInstallationSource?,
        extensionID: String
    ) -> Bool {
        guard let source else {
            return true
        }
        switch source {
        case .unpackedPackage:
            return true
        case .localPackage(let localSource):
            return localSource.extensionID == extensionID
                && isSafeIdentifier(localSource.extensionID)
                && isSHA256Hex(localSource.sha256Hex)
        case .safariWebExtension(let safariSource):
            guard !safariSource.applicationBookmark.isEmpty,
                isSafeIdentifier(
                    safariSource.applicationBundleIdentifier
                ),
                safariSource.extensionBundleIdentifier == extensionID,
                isSafeIdentifier(safariSource.extensionBundleIdentifier),
                isSafeSafariExtensionPath(
                    safariSource.relativeBundlePath
                )
            else {
                return false
            }
            return safariSource.developerTeamIdentifier.map(isSafeIdentifier)
                ?? true
        case .chromeWebStore(let chromeSource):
            guard chromeSource.extensionID.rawValue == extensionID,
                BrowserChromeWebStoreItem(url: chromeSource.storeURL)?.id
                    == chromeSource.extensionID,
                isSHA256Hex(chromeSource.crxSHA256Hex),
                chromeSource.publisherKeyHashHex
                    == BrowserCRX3Verifier.chromeWebStorePublisherKeyHash
                    .hexString
            else {
                return false
            }
            return true
        case .mozillaAddons(let mozillaSource):
            guard mozillaSource.extensionID.rawValue == extensionID,
                BrowserMozillaAddonsItem(url: mozillaSource.storeURL)?.slug
                    == mozillaSource.slug,
                isSHA256Hex(mozillaSource.xpiSHA256Hex),
                isSafeVersion(mozillaSource.version)
            else {
                return false
            }
            return true
        }
    }

    private static func isSafeVersion(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= maximumVersionLength else {
            return false
        }
        return value.utf8.allSatisfy { byte in
            (0x30...0x39).contains(byte)
                || (0x61...0x7a).contains(byte)
                || (0x41...0x5a).contains(byte)
                || byte == 0x2e
                || byte == 0x2d
                || byte == 0x2b
                || byte == 0x5f
        }
    }

    private static func isSHA256Hex(_ value: String) -> Bool {
        value.utf8.count == 64
            && value.utf8.allSatisfy {
                (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
            }
    }

    private static func isSafeSafariExtensionPath(
        _ relativePath: String
    ) -> Bool {
        guard !relativePath.hasPrefix("/"),
            !relativePath.contains("\\")
        else {
            return false
        }
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard components.count == 3,
            components[0] == "Contents",
            components[1] == "PlugIns",
            !components[2].isEmpty,
            components[2] != ".",
            components[2] != ".."
        else {
            return false
        }
        return URL(fileURLWithPath: components[2])
            .pathExtension.lowercased() == "appex"
    }
}
