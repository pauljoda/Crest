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

/// What the compatibility runtime's diagnostics channel reported.
///
/// The kinds are the extension's own faults, not Crest's: an uncaught
/// exception, an unhandled promise rejection, a `runtime.lastError` nobody
/// read, and — when a build enables console capture — the extension's own
/// console output and a trace of the messages it sends and receives, which
/// together are the only trace a *hang* leaves behind.
enum BrowserExtensionDiagnosticsReportKind: String {
    case uncaughtError = "error"
    case unhandledRejection = "unhandledrejection"
    case uncheckedLastError = "lastError"
    case consoleOutput = "console"
    case messageTrace = "trace"
    case suppressed

    var label: String {
        switch self {
        case .uncaughtError: "Uncaught error"
        case .unhandledRejection: "Unhandled promise rejection"
        case .uncheckedLastError: "Unchecked runtime.lastError"
        case .consoleOutput: "Console"
        case .messageTrace: "Message trace"
        case .suppressed: "Diagnostics suppressed"
        }
    }

    /// Whether this report belongs in the extension's *Needs attention*
    /// errors.
    ///
    /// Only the two kinds that mean the extension's code actually stopped
    /// running. Console output and message traces are routine even in a
    /// healthy extension, an unread `runtime.lastError` is a callback-hygiene
    /// warning rather than a failure, and the suppression notice is about
    /// Crest's own budget — none of them should light up a working
    /// extension's row in settings, so they stay in the log only.
    var appendsToRuntimeSummaryErrors: Bool {
        switch self {
        case .uncaughtError, .unhandledRejection: true
        case .uncheckedLastError, .consoleOutput, .messageTrace, .suppressed:
            false
        }
    }
}

/// What an extension's own JavaScript reported about itself.
///
/// WebKit hands `WKWebExtensionContext.errors` only what an API callback threw.
/// An uncaught exception or an unhandled rejection in a popup, an extension
/// page, or a background worker reaches nobody — Chrome records exactly those
/// on the extension's error page, and their absence is why a Bitwarden popup
/// could go blank after a two-factor sign-in with nothing to read afterwards.
/// The runtime's diagnostics channel sends them to Crest's capability broker,
/// which files them here so `summary(for:)` can merge them into the errors the
/// Extensions settings screen already shows under *Needs attention*.
///
/// Deliberately in memory only, and bounded per context: this is a live
/// troubleshooting aid, not an installation record. Whatever a runtime summary
/// already persists it keeps persisting — nothing here writes to the registry
/// on its own.
@MainActor
final class BrowserExtensionDiagnosticsLog {
    /// One log for the process. The writer is a WebKit delegate callback on a
    /// coordinator that holds no persistence, and the reader is the summary
    /// builder; both address entries by `WKWebExtensionContext
    /// .uniqueIdentifier`, which is already scoped to one extension in one
    /// Space. Every injection point defaults to this instance, so a test can
    /// still supply its own.
    static let shared = BrowserExtensionDiagnosticsLog()

    /// Posted after `record`, carrying the affected context's unique
    /// identifier in `contextIdentifierKey`. `BrowserExtensionContextObserver`
    /// turns it into the same runtime-summary refresh WebKit's own
    /// `errorsDidUpdateNotification` drives.
    static let didRecordNotification = Notification.Name(
        "BrowserExtensionDiagnosticsLogDidRecord"
    )
    static let contextIdentifierKey = "contextIdentifier"

    private static let capacity = 20

    private var entriesByContext: [String: [String]] = [:]

    /// Files one entry, dropping the oldest once the context is at capacity.
    func record(_ entry: String, forContext contextIdentifier: String) {
        guard !entry.isEmpty, !contextIdentifier.isEmpty else { return }
        var entries = entriesByContext[contextIdentifier] ?? []
        entries.append(entry)
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
        entriesByContext[contextIdentifier] = entries
        NotificationCenter.default.post(
            name: Self.didRecordNotification,
            object: nil,
            userInfo: [Self.contextIdentifierKey: contextIdentifier]
        )
    }

    /// Oldest first, matching the order the extension reported them in.
    func entries(forContext contextIdentifier: String) -> [String] {
        entriesByContext[contextIdentifier] ?? []
    }

    func removeEntries(forContext contextIdentifier: String) {
        entriesByContext.removeValue(forKey: contextIdentifier)
    }
}

@Observable
@MainActor
final class BrowserExtensionPersistenceController {
    @ObservationIgnored private let packageStore: any BrowserExtensionPackageStoring
    @ObservationIgnored private let registry: BrowserExtensionRegistry
    @ObservationIgnored private let diagnosticsLog: BrowserExtensionDiagnosticsLog

    private(set) var summariesBySpace: [SpaceID: [BrowserExtensionSummary]] = [:]

    init(
        packageStore: any BrowserExtensionPackageStoring,
        registry: BrowserExtensionRegistry,
        diagnosticsLog: BrowserExtensionDiagnosticsLog = .shared
    ) {
        self.packageStore = packageStore
        self.registry = registry
        self.diagnosticsLog = diagnosticsLog
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

    func stage(
        _ package: BrowserLocalExtensionPackage,
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
        permissionSnapshot: BrowserExtensionPermissionSnapshot,
        excluding excludedPermissions: Set<String> = [],
        source: BrowserExtensionInstallationSource? = nil
    ) -> BrowserExtensionSummary {
        let runtimeReport = BrowserExtensionRuntimeReport(
            errors: context.webExtension.errors + context.errors
        )
        // What the extension's own JavaScript reported about itself, which
        // WebKit's error list never carries. Appended after WebKit's entries
        // and in report order, so the newest fault reads last.
        let reportedDiagnostics = diagnosticsLog.entries(
            forContext: context.uniqueIdentifier
        ).filter { !runtimeReport.errors.contains($0) }
        let requestedPermissions = context.webExtension.requestedPermissions
            .map(\.rawValue)
            .filter { !excludedPermissions.contains($0) }
            .sorted()
        // The runtime hides two different things through one WebKit property.
        // Everything the compatibility matrix contributes is a Crest routing
        // decision, recomputed from these permissions on every load. It is
        // dropped here so it never reaches the installation record — a
        // persisted hide would be unioned back forever and no later matrix
        // change could un-hide it — and so the extension's "Unsupported APIs"
        // list shows only entries a person can act on.
        //
        // This has to ask the same question `load` asked, on the same axis. A
        // Safari-sourced extension gets no matrix hides at all, so subtracting
        // them here would delete entries WebKit itself reported and leave that
        // extension's "Unsupported APIs" list falsely empty.
        let platformUnsupportedAPIs = Self.platformUnsupportedWebKitAPIs(
            requestedPermissions: requestedPermissions,
            source: source
        )
        return BrowserExtensionSummary(
            id: extensionID,
            displayName: context.webExtension.displayName ?? extensionID,
            version: context.webExtension.displayVersion
                ?? context.webExtension.version,
            requestedPermissions: requestedPermissions,
            requestedHosts: context.webExtension.allRequestedMatchPatterns
                .map(\.string)
                .sorted(),
            unsupportedAPIs: context.unsupportedAPIs
                .subtracting(platformUnsupportedAPIs)
                .sorted(),
            errors: runtimeReport.errors + reportedDiagnostics,
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

    /// The hides Crest itself contributes to `context.unsupportedAPIs`.
    ///
    /// The one place that answers the question, so the summary can never
    /// subtract a set the loader did not add. Mirrors the switch in
    /// `BrowserExtensionRuntimeContextController.load`.
    static func platformUnsupportedWebKitAPIs(
        requestedPermissions: [String],
        source: BrowserExtensionInstallationSource?
    ) -> Set<String> {
        switch source {
        case .some(.safariWebExtension):
            []
        default:
            BrowserExtensionAPICompatibilityMatrix
                .unsupportedWebKitAPIs(
                    requestedPermissions: requestedPermissions
                )
        }
    }

    func summary(
        for context: WKWebExtensionContext,
        installation: BrowserExtensionInstallation,
        permissionSnapshot: BrowserExtensionPermissionSnapshot,
        excluding excludedPermissions: Set<String> = []
    ) -> BrowserExtensionSummary {
        var runtimeSummary = summary(
            for: context,
            extensionID: installation.id,
            isEnabled: installation.isEnabled,
            permissionSnapshot: permissionSnapshot,
            excluding: excludedPermissions,
            source: installation.source
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
                || previous.source?.isLocalPackage == true
        else {
            return
        }
        try? removePackage(
            packageName: previous.packageName,
            in: spaceID
        )
    }
}
