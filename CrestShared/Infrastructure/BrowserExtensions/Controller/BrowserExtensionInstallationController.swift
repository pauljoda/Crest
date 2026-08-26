import Foundation
import WebKit

@MainActor
final class BrowserExtensionInstallationController {
    let persistence: BrowserExtensionPersistenceController
    let runtime: BrowserExtensionRuntimeContextController
    let webpageMenuRegistry: BrowserExtensionWebpageMenuRegistry
    private let storedResourcePreparer: any BrowserExtensionStoredResourcePreparing

    init(
        persistence: BrowserExtensionPersistenceController,
        runtime: BrowserExtensionRuntimeContextController,
        webpageMenuRegistry: BrowserExtensionWebpageMenuRegistry,
        storedResourcePreparer:
            any BrowserExtensionStoredResourcePreparing
    ) {
        self.persistence = persistence
        self.runtime = runtime
        self.webpageMenuRegistry = webpageMenuRegistry
        self.storedResourcePreparer = storedResourcePreparer
    }

    func loadExtension(
        at resourceBaseURL: URL,
        extensionID: String,
        in space: BrowserSpace,
        unsupportedAPIs: Set<String>,
        source: BrowserExtensionInstallationSource?,
        permissionSnapshot: BrowserExtensionPermissionSnapshot
    ) async throws -> WKWebExtensionContext {
        try await runtime.loadExtension(
            at: resourceBaseURL,
            extensionID: extensionID,
            in: space,
            unsupportedAPIs: unsupportedAPIs,
            permissionSnapshot: permissionSnapshot,
            persistsRuntimeSummary: false,
            source: source
        )
    }

    func loadUnpackedExtension(
        from sourceURL: URL,
        in space: BrowserSpace
    ) async throws -> BrowserExtensionSummary {
        let package = try persistence.stage(sourceURL, in: space.id)
        let previous = persistence.installation(
            extensionID: package.extensionID,
            in: space.id
        )
        let source = BrowserExtensionInstallationSource.unpackedPackage
        var didLoadNewContext = false
        var pendingLifecycle: PendingContextMenuInstallLifecycle?
        do {
            // Inspect the staged copy without loading its background content.
            // The requested permissions determine whether the platform-owned
            // compatibility overlay is needed before the first real load.
            let inspectedExtension = try await WKWebExtension(
                resourceBaseURL: package.resourceURL
            )
            let requestedPermissions = inspectedExtension
                .requestedPermissions.map(\.rawValue).sorted()
            let permissionSnapshot =
                previous?.permissionSnapshot
                ?? BrowserExtensionPermissionSnapshot(
                    grantedPermissions: Dictionary(
                        uniqueKeysWithValues: requestedPermissions.filter {
                            $0 == "contextMenus" || $0 == "menus"
                        }.map { ($0, Date.distantFuture) }
                    )
                )
            let preparedResource = try storedResourcePreparer.prepare(
                resourceURL: package.resourceURL,
                request: BrowserExtensionStoredResourcePreparationRequest(
                    extensionID: package.extensionID,
                    source: source,
                    spaceID: space.id,
                    requestedPermissions: requestedPermissions
                )
            )
            pendingLifecycle = prepareContextMenuInstallLifecycle(
                previous: previous,
                extensionID: package.extensionID,
                spaceID: space.id,
                requestedPermissions: requestedPermissions
            )
            // An unpacked folder keeps one identity across imports, so a second
            // import is a reload. Release the running context only after the
            // replacement has been inspected and prepared successfully.
            if let loaded = runtime.loadedContext(
                extensionID: package.extensionID,
                in: space.id
            ) {
                try runtime.controller(for: space).unload(loaded)
                runtime.releaseContext(
                    extensionID: package.extensionID,
                    in: space.id
                )
            }
            let context = try await runtime.loadExtension(
                at: preparedResource.resourceURL,
                extensionID: package.extensionID,
                in: space,
                unsupportedAPIs: [],
                permissionSnapshot: permissionSnapshot,
                persistsRuntimeSummary: false,
                source: source,
                internalGrantedPermissions:
                    preparedResource.internalGrantedPermissions
            )
            didLoadNewContext = true
            var summary = runtime.summary(
                for: context,
                extensionID: package.extensionID,
                isEnabled: true
            )
            summary.isPinned = previous?.isPinned == true
            let now = Date.now
            let installation = BrowserExtensionInstallation(
                id: package.extensionID,
                spaceID: space.id,
                packageName: package.packageName,
                source: source,
                displayName: summary.displayName,
                version: summary.version,
                requestedPermissions: summary.requestedPermissions,
                requestedHosts: summary.requestedHosts,
                unsupportedAPIs: summary.unsupportedAPIs,
                errors: summary.errors,
                isEnabled: true,
                permissionSnapshot: summary.permissionSnapshot,
                installedAt: previous?.installedAt ?? now,
                modifiedAt: now,
                hasOptionsPage: summary.hasOptionsPage,
                hasCommands: summary.hasCommands,
                isPinned: previous?.isPinned,
                commandShortcutOverrides:
                    previous?.commandShortcutOverrides
            )
            guard persistence.upsert(installation) else {
                try? runtime.controller(for: space).unload(context)
                runtime.releaseContext(
                    extensionID: package.extensionID,
                    in: space.id
                )
                throw BrowserExtensionControllerPoolError
                    .invalidInstallationRecord
            }
            persistence.removeReplacedPackageIfNeeded(
                previous,
                retaining: package.packageName,
                in: space.id
            )
            persistence.updateSummary(summary, in: space.id)
            if let retainedAccess = preparedResource.retainedAccess {
                runtime.retainRuntimeResourceAccess(
                    retainedAccess,
                    extensionID: package.extensionID,
                    in: space.id
                )
            }
            return summary
        } catch {
            cancelContextMenuInstallLifecycle(pendingLifecycle)
            if didLoadNewContext,
                let context = runtime.loadedContext(
                    extensionID: package.extensionID,
                    in: space.id
                )
            {
                try? runtime.controller(for: space).unload(context)
                runtime.releaseContext(
                    extensionID: package.extensionID,
                    in: space.id
                )
            }
            persistence.discard(package)
            await restorePreviousInstallation(
                previous,
                extensionID: package.extensionID,
                in: space
            )
            throw error
        }
    }

    func removeExtension(
        extensionID: String,
        from space: BrowserSpace
    ) async throws {
        guard
            let installation = persistence.installation(
                extensionID: extensionID,
                in: space.id
            )
        else {
            return
        }
        let controller = runtime.controller(for: space)
        if let context = runtime.loadedContext(
            extensionID: extensionID,
            in: space.id
        ) {
            try controller.unload(context)
            runtime.releaseContext(extensionID: extensionID, in: space.id)
        }
        let storedData = await controller.dataRecords(
            ofTypes: WKWebExtensionController.allExtensionDataTypes
        )
        let runtimeIdentifier =
            BrowserExtensionRuntimeIdentifierPolicy
            .identifier(
                extensionID: extensionID,
                source: installation.source,
                spaceID: space.id
            )
        if let dataRecord = storedData.first(where: {
            $0.uniqueIdentifier == runtimeIdentifier
        }) {
            await removeStoredData(dataRecord, from: controller)
        }
        if shouldRemovePackage(for: installation) {
            try persistence.removePackage(
                packageName: installation.packageName,
                in: space.id
            )
        }
        _ = persistence.remove(extensionID: extensionID, from: space.id)
        persistence.removeSummary(extensionID: extensionID, in: space.id)
    }

    func deleteData(
        for space: BrowserSpace
    ) async throws -> BrowserSpaceDataReleaseProbe {
        let controller = runtime.controller(for: space)
        let releaseProbe = BrowserSpaceDataReleaseProbe(controller)
        for (extensionID, context) in runtime.contexts(in: space.id) {
            try controller.unload(context)
            runtime.releaseContext(extensionID: extensionID, in: space.id)
        }

        let storedData = await controller.dataRecords(
            ofTypes: WKWebExtensionController.allExtensionDataTypes
        )
        if !storedData.isEmpty {
            await withCheckedContinuation { continuation in
                controller.removeData(
                    ofTypes: WKWebExtensionController.allExtensionDataTypes,
                    from: storedData
                ) {
                    continuation.resume()
                }
            }
        }

        try persistence.removePackages(in: space.id)
        persistence.removeAll(in: space.id)
        persistence.removeSummaries(in: space.id)
        runtime.removeSpace(space.id)
        return releaseProbe
    }

    private func removeStoredData(
        _ dataRecord: WKWebExtension.DataRecord,
        from controller: WKWebExtensionController
    ) async {
        await withCheckedContinuation { continuation in
            controller.removeData(
                ofTypes: WKWebExtensionController.allExtensionDataTypes,
                from: [dataRecord]
            ) {
                continuation.resume()
            }
        }
    }

    private func shouldRemovePackage(
        for installation: BrowserExtensionInstallation
    ) -> Bool {
        installation.source == nil
            || installation.source == .unpackedPackage
            || installation.source?.isChromeWebStore == true
            || installation.source?.isLocalPackage == true
    }

    struct PendingContextMenuInstallLifecycle {
        let clientID: BrowserExtensionServiceClientID
        let eventID: String
    }

    func prepareContextMenuInstallLifecycle(
        previous: BrowserExtensionInstallation?,
        extensionID: String,
        spaceID: SpaceID,
        requestedPermissions: [String]
    ) -> PendingContextMenuInstallLifecycle? {
        guard
            requestedPermissions.contains("contextMenus")
                || requestedPermissions.contains("menus")
        else { return nil }
        let clientID = BrowserExtensionServiceClientID.scoped(
            extensionID: extensionID,
            spaceID: spaceID
        )
        let eventID = webpageMenuRegistry.prepareInstallLifecycle(
            reason: previous == nil ? .install : .update,
            previousVersion: previous?.version,
            for: clientID
        )
        return PendingContextMenuInstallLifecycle(
            clientID: clientID,
            eventID: eventID
        )
    }

    func cancelContextMenuInstallLifecycle(
        _ pending: PendingContextMenuInstallLifecycle?
    ) {
        guard let pending else { return }
        webpageMenuRegistry.cancelInstallLifecycle(
            eventID: pending.eventID,
            for: pending.clientID
        )
    }

    func restorePreviousInstallation(
        _ previous: BrowserExtensionInstallation?,
        extensionID: String,
        in space: BrowserSpace
    ) async {
        guard let previous else {
            persistence.removeSummary(
                extensionID: extensionID,
                in: space.id
            )
            return
        }
        if previous.isEnabled {
            _ = try? await runtime.loadInstallation(previous, in: space)
        } else {
            persistence.updateSummary(
                persistence.summary(
                    for: previous,
                    nativeMessagingCapability:
                        runtime.nativeMessagingCapability
                ),
                in: space.id
            )
        }
    }
}
