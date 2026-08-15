import Foundation
import WebKit

@MainActor
final class BrowserExtensionInstallationController {
    let persistence: BrowserExtensionPersistenceController
    let runtime: BrowserExtensionRuntimeContextController

    init(
        persistence: BrowserExtensionPersistenceController,
        runtime: BrowserExtensionRuntimeContextController
    ) {
        self.persistence = persistence
        self.runtime = runtime
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
        // An unpacked folder now keeps one identity across imports, so a second
        // import of the same folder is a reload. Release the running context
        // first, otherwise the already-loaded one would be handed back and the
        // edited files on disk would never be read.
        if let loaded = runtime.loadedContext(
            extensionID: package.extensionID,
            in: space.id
        ) {
            try? runtime.controller(for: space).unload(loaded)
            runtime.releaseContext(
                extensionID: package.extensionID,
                in: space.id
            )
        }
        do {
            let context = try await runtime.loadExtension(
                at: package.resourceURL,
                extensionID: package.extensionID,
                in: space,
                unsupportedAPIs: [],
                permissionSnapshot: .empty,
                persistsRuntimeSummary: false,
                source: nil
            )
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
            return summary
        } catch {
            persistence.discard(package)
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
    }
}
