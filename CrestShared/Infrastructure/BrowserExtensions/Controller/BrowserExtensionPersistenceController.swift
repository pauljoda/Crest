import Foundation
import Observation
import WebKit

struct BrowserExtensionRuntimeReport {
    private static let scriptExecutionErrorCode = 7

    let errors: [String]
    let diagnostics: [String]

    init(errors reportedErrors: [any Error]) {
        var errors: Set<String> = []
        var diagnostics: Set<String> = []
        for reportedError in reportedErrors {
            let error = reportedError as NSError
            let description = error.localizedDescription
            guard !description.isEmpty else { continue }
            if Self.isDiagnostic(error) {
                diagnostics.insert(description)
            } else {
                errors.insert(description)
            }
        }
        diagnostics.subtract(errors)
        self.errors = errors.sorted()
        self.diagnostics = diagnostics.sorted()
    }

    private static func isDiagnostic(_ error: NSError) -> Bool {
        if error.domain == WKWebExtensionContext.errorDomain {
            // WebKit records JavaScript execution messages as private context
            // error code 7. They are useful extension logs, but do not mean the
            // context or its background content failed to load.
            return error.code == scriptExecutionErrorCode
        }
        if error.domain == WKWebExtension.errorDomain {
            return [
                WKWebExtension.Error.invalidManifestEntry.rawValue,
                WKWebExtension.Error.invalidDeclarativeNetRequestEntry
                    .rawValue,
                WKWebExtension.Error.invalidBackgroundPersistence.rawValue,
            ].contains(error.code)
        }
        return false
    }
}

@Observable
@MainActor
final class BrowserExtensionPersistenceController {
    @ObservationIgnored private let packageStore: any BrowserExtensionPackageStoring
    @ObservationIgnored private let registry: BrowserExtensionRegistry

    private(set) var summariesBySpace: [SpaceID: [BrowserExtensionSummary]] = [:]

    init(
        packageStore: any BrowserExtensionPackageStoring,
        registry: BrowserExtensionRegistry
    ) {
        self.packageStore = packageStore
        self.registry = registry
    }

    var installations: [BrowserExtensionInstallation] {
        registry.installations
    }

    func installations(
        in spaceID: SpaceID
    ) -> [BrowserExtensionInstallation] {
        registry.installations(in: spaceID)
    }

    func installation(
        extensionID: String,
        in spaceID: SpaceID
    ) -> BrowserExtensionInstallation? {
        registry.installation(extensionID: extensionID, in: spaceID)
    }

    @discardableResult
    func upsert(_ installation: BrowserExtensionInstallation) -> Bool {
        registry.upsert(installation)
    }

    func setEnabled(
        _ enabled: Bool,
        extensionID: String,
        in spaceID: SpaceID
    ) {
        registry.setEnabled(enabled, extensionID: extensionID, in: spaceID)
    }

    func setPinned(
        _ pinned: Bool,
        extensionID: String,
        in spaceID: SpaceID
    ) {
        registry.setPinned(pinned, extensionID: extensionID, in: spaceID)
    }

    func setCommandShortcutOverride(
        _ override: BrowserExtensionCommandShortcutOverride,
        commandID: String,
        extensionID: String,
        in spaceID: SpaceID
    ) {
        registry.setCommandShortcutOverride(
            override,
            commandID: commandID,
            extensionID: extensionID,
            in: spaceID
        )
    }

    func resetCommandShortcutOverride(
        commandID: String,
        extensionID: String,
        in spaceID: SpaceID
    ) {
        registry.resetCommandShortcutOverride(
            commandID: commandID,
            extensionID: extensionID,
            in: spaceID
        )
    }

    func updatePermissionSnapshot(
        _ snapshot: BrowserExtensionPermissionSnapshot,
        extensionID: String,
        in spaceID: SpaceID
    ) {
        registry.updatePermissionSnapshot(
            snapshot,
            extensionID: extensionID,
            in: spaceID
        )
    }

    func updateRuntimeSummary(
        _ summary: BrowserExtensionSummary,
        extensionID: String,
        in spaceID: SpaceID
    ) {
        registry.updateRuntimeSummary(
            displayName: summary.displayName,
            version: summary.version,
            requestedPermissions: summary.requestedPermissions,
            requestedHosts: summary.requestedHosts,
            unsupportedAPIs: summary.unsupportedAPIs,
            errors: summary.errors,
            extensionID: extensionID,
            in: spaceID
        )
    }

    @discardableResult
    func remove(
        extensionID: String,
        from spaceID: SpaceID
    ) -> BrowserExtensionInstallation? {
        registry.remove(extensionID: extensionID, from: spaceID)
    }

    func removeAll(in spaceID: SpaceID) {
        registry.removeAll(in: spaceID)
    }

    func stage(
        _ sourceURL: URL,
        in spaceID: SpaceID
    ) throws -> BrowserExtensionPackage {
        try packageStore.stage(sourceURL, in: spaceID)
    }

    func stage(
        _ package: BrowserVerifiedCRX3Package,
        in spaceID: SpaceID
    ) throws -> BrowserExtensionPackage {
        try packageStore.stage(package, in: spaceID)
    }

    func stage(
        _ package: BrowserVerifiedXPIPackage,
        in spaceID: SpaceID
    ) throws -> BrowserExtensionPackage {
        try packageStore.stage(package, in: spaceID)
    }

    func stageVerifiedChromeResource(
        _ sourceURL: URL,
        extensionID: BrowserChromeExtensionID,
        in spaceID: SpaceID
    ) throws -> BrowserExtensionPackage {
        try packageStore.stageVerifiedChromeResource(
            sourceURL,
            extensionID: extensionID,
            in: spaceID
        )
    }

    func resourceURL(
        packageName: String,
        in spaceID: SpaceID
    ) throws -> URL {
        try packageStore.resourceURL(packageName: packageName, in: spaceID)
    }

    func discard(_ package: BrowserExtensionPackage) {
        packageStore.discard(package)
    }

    func removePackage(
        packageName: String,
        in spaceID: SpaceID
    ) throws {
        try packageStore.removePackage(packageName: packageName, in: spaceID)
    }

    func removePackages(in spaceID: SpaceID) throws {
        try packageStore.removePackages(in: spaceID)
    }

    func extensions(
        in spaceID: SpaceID,
        nativeMessagingCapability: BrowserExtensionNativeMessagingCapability
    ) -> [BrowserExtensionSummary] {
        summariesBySpace[spaceID]
            ?? installations(in: spaceID).map {
                summary(
                    for: $0,
                    nativeMessagingCapability: nativeMessagingCapability
                )
            }
    }

    func replaceSummaries(
        in spaceID: SpaceID,
        nativeMessagingCapability: BrowserExtensionNativeMessagingCapability
    ) {
        summariesBySpace[spaceID] = installations(in: spaceID).map {
            summary(
                for: $0,
                nativeMessagingCapability: nativeMessagingCapability
            )
        }
    }

    func summary(
        for context: WKWebExtensionContext,
        extensionID: String,
        isEnabled: Bool,
        permissionSnapshot: BrowserExtensionPermissionSnapshot
    ) -> BrowserExtensionSummary {
        let runtimeReport = BrowserExtensionRuntimeReport(
            errors: context.webExtension.errors + context.errors
        )
        return BrowserExtensionSummary(
            id: extensionID,
            displayName: context.webExtension.displayName ?? extensionID,
            version: context.webExtension.displayVersion
                ?? context.webExtension.version,
            requestedPermissions: context.webExtension.requestedPermissions
                .map(\.rawValue)
                .sorted(),
            requestedHosts: context.webExtension.allRequestedMatchPatterns
                .map(\.string)
                .sorted(),
            unsupportedAPIs: context.unsupportedAPIs.sorted(),
            errors: runtimeReport.errors,
            diagnostics: runtimeReport.diagnostics,
            isEnabled: isEnabled,
            isLoaded: context.isLoaded,
            permissionSnapshot: permissionSnapshot,
            hasOptionsPage: context.webExtension.hasOptionsPage,
            hasCommands: context.webExtension.hasCommands
        )
    }

    func summary(
        for installation: BrowserExtensionInstallation,
        nativeMessagingCapability: BrowserExtensionNativeMessagingCapability
    ) -> BrowserExtensionSummary {
        let compatibilityAssessment = BrowserExtensionCompatibilityPolicy.assess(
            requestedPermissions: installation.requestedPermissions,
            source: BrowserExtensionCompatibilitySource(
                installationSource: installation.source
            ),
            nativeMessagingCapability: nativeMessagingCapability
        )
        return BrowserExtensionSummary(
            id: installation.id,
            displayName: installation.displayName,
            version: installation.version,
            requestedPermissions: installation.requestedPermissions,
            requestedHosts: installation.requestedHosts,
            unsupportedAPIs: installation.unsupportedAPIs,
            errors: installation.errors,
            isEnabled: installation.isEnabled,
            isLoaded: false,
            permissionSnapshot: installation.permissionSnapshot,
            compatibilitySource: BrowserExtensionCompatibilitySource(
                installationSource: installation.source
            ),
            compatibilityAssessment: compatibilityAssessment,
            sourceDisplayName: installation.sourceDisplayName,
            iconPayload: BrowserExtensionIconPayloadFactory.production.payload(
                for: installation.iconData
            ),
            hasOptionsPage: installation.hasOptionsPage ?? false,
            hasCommands: installation.hasCommands ?? false,
            isPinned: installation.isPinned == true
        )
    }

    func summary(
        for context: WKWebExtensionContext,
        installation: BrowserExtensionInstallation,
        permissionSnapshot: BrowserExtensionPermissionSnapshot
    ) -> BrowserExtensionSummary {
        var runtimeSummary = summary(
            for: context,
            extensionID: installation.id,
            isEnabled: installation.isEnabled,
            permissionSnapshot: permissionSnapshot
        )
        runtimeSummary.sourceDisplayName = installation.sourceDisplayName
        runtimeSummary.compatibilitySource =
            BrowserExtensionCompatibilitySource(
                installationSource: installation.source
            )
        runtimeSummary.iconPayload = BrowserExtensionIconPayloadFactory
            .production.payload(for: installation.iconData)
        runtimeSummary.hasOptionsPage =
            installation.hasOptionsPage ?? runtimeSummary.hasOptionsPage
        runtimeSummary.hasCommands =
            installation.hasCommands ?? runtimeSummary.hasCommands
        runtimeSummary.isPinned = installation.isPinned == true
        return runtimeSummary
    }

    func updateSummary(
        _ summary: BrowserExtensionSummary,
        in spaceID: SpaceID
    ) {
        var summaries = summariesBySpace[spaceID] ?? []
        summaries.removeAll { $0.id == summary.id }
        summaries.append(summary)
        summaries.sort {
            $0.displayName.localizedStandardCompare($1.displayName)
                == .orderedAscending
        }
        summariesBySpace[spaceID] = summaries
    }

    func removeSummary(extensionID: String, in spaceID: SpaceID) {
        summariesBySpace[spaceID]?.removeAll { $0.id == extensionID }
    }

    func removeSummaries(in spaceID: SpaceID) {
        summariesBySpace.removeValue(forKey: spaceID)
    }

    func recordRestoreFailure(
        _ error: any Error,
        installation: BrowserExtensionInstallation,
        nativeMessagingCapability: BrowserExtensionNativeMessagingCapability
    ) {
        var failed = installation
        failed.errors = Array(
            Set(failed.errors + [error.localizedDescription])
        ).sorted()
        registry.updateRuntimeSummary(
            displayName: failed.displayName,
            version: failed.version,
            requestedPermissions: failed.requestedPermissions,
            requestedHosts: failed.requestedHosts,
            unsupportedAPIs: failed.unsupportedAPIs,
            errors: failed.errors,
            extensionID: failed.id,
            in: failed.spaceID
        )
        updateSummary(
            summary(
                for: failed,
                nativeMessagingCapability: nativeMessagingCapability
            ),
            in: installation.spaceID
        )
    }

    func removeReplacedPackageIfNeeded(
        _ previous: BrowserExtensionInstallation?,
        retaining packageName: String,
        in spaceID: SpaceID
    ) {
        guard let previous,
            previous.packageName != packageName,
            previous.source == nil
                || previous.source == .unpackedPackage
                || previous.source?.isChromeWebStore == true
        else {
            return
        }
        try? removePackage(
            packageName: previous.packageName,
            in: spaceID
        )
    }
}
