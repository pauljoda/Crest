import Foundation

extension BrowserExtensionInstallationController {
    func installSafariWebExtension(
        _ candidate: BrowserSafariWebExtensionCandidate,
        in space: BrowserSpace
    ) async throws -> BrowserExtensionSummary {
        let extensionID = candidate.source.extensionBundleIdentifier
        let previous = persistence.installation(
            extensionID: extensionID,
            in: space.id
        )
        if let existingContext = runtime.loadedContext(
            extensionID: extensionID,
            in: space.id
        ) {
            try runtime.controller(for: space).unload(existingContext)
            runtime.releaseContext(extensionID: extensionID, in: space.id)
        }

        let resource = try await BrowserPlatformSafariWebExtensionLoader.load(
            candidate.source
        )
        let context = try runtime.load(
            webExtension: resource.webExtension,
            extensionID: extensionID,
            in: space,
            unsupportedAPIs: [],
            permissionSnapshot: previous?.permissionSnapshot
                ?? BrowserExtensionInstallationPermissionPolicy
                .reviewedRequiredAccess(
                    permissions: candidate.requestedPermissions,
                    hosts: candidate.requestedHosts
                ),
            persistsRuntimeSummary: false,
            source: .safariWebExtension(candidate.source)
        )
        runtime.retainRuntimeResourceAccess(
            resource.access,
            extensionID: extensionID,
            in: space.id
        )

        var runtimeSummary = runtime.summary(
            for: context,
            extensionID: extensionID,
            isEnabled: true
        )
        runtimeSummary.sourceDisplayName = candidate.applicationDisplayName
        runtimeSummary.iconPayload = candidate.iconPayload
        runtimeSummary.hasOptionsPage = candidate.hasOptionsPage
        runtimeSummary.hasCommands = candidate.hasCommands
        runtimeSummary.isPinned = previous?.isPinned == true

        let now = Date.now
        let installation = BrowserExtensionInstallation(
            id: extensionID,
            spaceID: space.id,
            packageName: extensionID,
            source: .safariWebExtension(candidate.source),
            displayName: runtimeSummary.displayName,
            version: runtimeSummary.version,
            requestedPermissions: runtimeSummary.requestedPermissions,
            requestedHosts: runtimeSummary.requestedHosts,
            unsupportedAPIs: runtimeSummary.unsupportedAPIs,
            errors: runtimeSummary.errors,
            isEnabled: true,
            permissionSnapshot: runtimeSummary.permissionSnapshot,
            installedAt: previous?.installedAt ?? now,
            modifiedAt: now,
            sourceDisplayName: candidate.applicationDisplayName,
            iconData: candidate.iconData,
            hasOptionsPage: candidate.hasOptionsPage,
            hasCommands: candidate.hasCommands,
            isPinned: previous?.isPinned,
            commandShortcutOverrides: previous?.commandShortcutOverrides
        )
        guard persistence.upsert(installation) else {
            try? runtime.controller(for: space).unload(context)
            runtime.releaseContext(extensionID: extensionID, in: space.id)
            throw BrowserExtensionControllerPoolError.invalidInstallationRecord
        }
        persistence.updateSummary(runtimeSummary, in: space.id)
        return runtimeSummary
    }

    func installChromeWebStoreExtension(
        _ candidate: BrowserChromeWebStoreCandidate,
        in space: BrowserSpace
    ) async throws -> BrowserExtensionSummary {
        let extensionID = candidate.source.extensionID.rawValue
        guard candidate.item.id == candidate.source.extensionID,
            candidate.verifiedPackage.extensionID
                == candidate.source.extensionID,
            candidate.source.crxSHA256Hex
                == candidate.verifiedPackage.crxSHA256Hex,
            candidate.source.publisherKeyHashHex
                == candidate.verifiedPackage.publisherKeyHashHex
        else {
            throw BrowserExtensionControllerPoolError.invalidInstallationRecord
        }
        guard candidate.compatibility.canRun else {
            throw BrowserExtensionCompatibilityError(
                assessment: candidate.compatibility
            )
        }
        let previous = persistence.installation(
            extensionID: extensionID,
            in: space.id
        )
        let package = try persistence.stage(
            candidate.verifiedPackage,
            in: space.id
        )
        let source = BrowserExtensionInstallationSource.chromeWebStore(
            candidate.source
        )
        var didLoadNewContext = false
        do {
            let compatibilityPackage = try prepareCompatibilityPackage(
                package,
                extensionID: extensionID,
                source: source,
                spaceID: space.id,
                requestedPermissions: candidate.requestedPermissions
            )
            if let existingContext = runtime.loadedContext(
                extensionID: extensionID,
                in: space.id
            ) {
                try runtime.controller(for: space).unload(existingContext)
                runtime.releaseContext(extensionID: extensionID, in: space.id)
            }
            let context = try await runtime.loadExtension(
                at: compatibilityPackage?.resourceURL
                    ?? package.resourceURL,
                extensionID: extensionID,
                in: space,
                unsupportedAPIs: Set(previous?.unsupportedAPIs ?? []),
                permissionSnapshot: previous?.permissionSnapshot
                    ?? BrowserExtensionInstallationPermissionPolicy
                    .reviewedRequiredAccess(
                        permissions: candidate.requestedPermissions,
                        hosts: candidate.requestedHosts
                    ),
                persistsRuntimeSummary: false,
                source: source
            )
            didLoadNewContext = true
            var runtimeSummary = runtime.summary(
                for: context,
                extensionID: extensionID,
                isEnabled: true
            )
            runtimeSummary.sourceDisplayName = "Chrome Web Store"
            runtimeSummary.iconPayload = candidate.iconPayload
            runtimeSummary.hasOptionsPage = candidate.hasOptionsPage
            runtimeSummary.hasCommands = candidate.hasCommands
            runtimeSummary.isPinned = previous?.isPinned == true

            let now = Date.now
            let installation = BrowserExtensionInstallation(
                id: extensionID,
                spaceID: space.id,
                packageName: package.packageName,
                source: source,
                displayName: runtimeSummary.displayName,
                version: runtimeSummary.version,
                requestedPermissions: runtimeSummary.requestedPermissions,
                requestedHosts: runtimeSummary.requestedHosts,
                unsupportedAPIs: runtimeSummary.unsupportedAPIs,
                errors: runtimeSummary.errors,
                isEnabled: true,
                permissionSnapshot: runtimeSummary.permissionSnapshot,
                installedAt: previous?.installedAt ?? now,
                modifiedAt: now,
                sourceDisplayName: "Chrome Web Store",
                iconData: candidate.iconData,
                hasOptionsPage: candidate.hasOptionsPage,
                hasCommands: candidate.hasCommands,
                isPinned: previous?.isPinned,
                commandShortcutOverrides: previous?.commandShortcutOverrides
            )
            guard persistence.upsert(installation) else {
                throw BrowserExtensionControllerPoolError
                    .invalidInstallationRecord
            }
            persistence.updateSummary(runtimeSummary, in: space.id)
            persistence.removeReplacedPackageIfNeeded(
                previous,
                retaining: package.packageName,
                in: space.id
            )
            if let compatibilityPackage {
                runtime.retainRuntimeResourceAccess(
                    compatibilityPackage,
                    extensionID: extensionID,
                    in: space.id
                )
            }
            return runtimeSummary
        } catch {
            if didLoadNewContext,
                let context = runtime.loadedContext(
                    extensionID: extensionID,
                    in: space.id
                )
            {
                try? runtime.controller(for: space).unload(context)
                runtime.releaseContext(extensionID: extensionID, in: space.id)
            }
            persistence.discard(package)
            await restorePreviousInstallation(
                previous,
                extensionID: extensionID,
                in: space
            )
            throw error
        }
    }

    func installMozillaAddonsExtension(
        _ candidate: BrowserMozillaAddonsCandidate,
        in space: BrowserSpace
    ) async throws -> BrowserExtensionSummary {
        let extensionID = candidate.source.extensionID.rawValue
        guard candidate.item.slug == candidate.source.slug,
            candidate.verifiedPackage.extensionID
                == candidate.source.extensionID,
            candidate.source.xpiSHA256Hex
                == candidate.verifiedPackage.xpiSHA256Hex
        else {
            throw BrowserExtensionControllerPoolError.invalidInstallationRecord
        }
        guard candidate.compatibility.canRun else {
            throw BrowserExtensionCompatibilityError(
                assessment: candidate.compatibility
            )
        }
        let previous = persistence.installation(
            extensionID: extensionID,
            in: space.id
        )
        let package = try persistence.stage(
            candidate.verifiedPackage,
            in: space.id
        )
        let source = BrowserExtensionInstallationSource.mozillaAddons(
            candidate.source
        )
        var didLoadNewContext = false
        do {
            let compatibilityPackage = try prepareCompatibilityPackage(
                package,
                extensionID: extensionID,
                source: source,
                spaceID: space.id,
                requestedPermissions: candidate.requestedPermissions
            )
            if let existingContext = runtime.loadedContext(
                extensionID: extensionID,
                in: space.id
            ) {
                try runtime.controller(for: space).unload(existingContext)
                runtime.releaseContext(extensionID: extensionID, in: space.id)
            }
            let context = try await runtime.loadExtension(
                at: compatibilityPackage?.resourceURL
                    ?? package.resourceURL,
                extensionID: extensionID,
                in: space,
                unsupportedAPIs: Set(previous?.unsupportedAPIs ?? []),
                permissionSnapshot: previous?.permissionSnapshot
                    ?? BrowserExtensionInstallationPermissionPolicy
                    .reviewedRequiredAccess(
                        permissions: candidate.requestedPermissions,
                        hosts: candidate.requestedHosts
                    ),
                persistsRuntimeSummary: false,
                source: source
            )
            didLoadNewContext = true
            var runtimeSummary = runtime.summary(
                for: context,
                extensionID: extensionID,
                isEnabled: true
            )
            runtimeSummary.sourceDisplayName = Self.mozillaAddonsDisplayName
            runtimeSummary.iconPayload = candidate.iconPayload
            runtimeSummary.hasOptionsPage = candidate.hasOptionsPage
            runtimeSummary.hasCommands = candidate.hasCommands
            runtimeSummary.isPinned = previous?.isPinned == true

            let now = Date.now
            let installation = BrowserExtensionInstallation(
                id: extensionID,
                spaceID: space.id,
                packageName: package.packageName,
                source: source,
                displayName: runtimeSummary.displayName,
                version: runtimeSummary.version,
                requestedPermissions: runtimeSummary.requestedPermissions,
                requestedHosts: runtimeSummary.requestedHosts,
                unsupportedAPIs: runtimeSummary.unsupportedAPIs,
                errors: runtimeSummary.errors,
                isEnabled: true,
                permissionSnapshot: runtimeSummary.permissionSnapshot,
                installedAt: previous?.installedAt ?? now,
                modifiedAt: now,
                sourceDisplayName: Self.mozillaAddonsDisplayName,
                iconData: candidate.iconData,
                hasOptionsPage: candidate.hasOptionsPage,
                hasCommands: candidate.hasCommands,
                isPinned: previous?.isPinned,
                commandShortcutOverrides: previous?.commandShortcutOverrides
            )
            guard persistence.upsert(installation) else {
                throw BrowserExtensionControllerPoolError
                    .invalidInstallationRecord
            }
            persistence.updateSummary(runtimeSummary, in: space.id)
            persistence.removeReplacedPackageIfNeeded(
                previous,
                retaining: package.packageName,
                in: space.id
            )
            if let compatibilityPackage {
                runtime.retainRuntimeResourceAccess(
                    compatibilityPackage,
                    extensionID: extensionID,
                    in: space.id
                )
            }
            return runtimeSummary
        } catch {
            if didLoadNewContext,
                let context = runtime.loadedContext(
                    extensionID: extensionID,
                    in: space.id
                )
            {
                try? runtime.controller(for: space).unload(context)
                runtime.releaseContext(extensionID: extensionID, in: space.id)
            }
            persistence.discard(package)
            await restorePreviousInstallation(
                previous,
                extensionID: extensionID,
                in: space
            )
            throw error
        }
    }

    func installLocalExtension(
        _ candidate: BrowserLocalExtensionCandidate,
        in space: BrowserSpace
    ) async throws -> BrowserExtensionSummary {
        let extensionID = candidate.id
        guard candidate.package.extensionID == extensionID,
            candidate.source.extensionID == extensionID,
            candidate.source.sha256Hex == candidate.package.sha256Hex
        else {
            throw BrowserExtensionControllerPoolError.invalidInstallationRecord
        }
        guard candidate.compatibility.canRun else {
            throw BrowserExtensionCompatibilityError(
                assessment: candidate.compatibility
            )
        }

        let previous = persistence.installation(
            extensionID: extensionID,
            in: space.id
        )
        let package = try persistence.stage(
            candidate.package,
            in: space.id
        )
        let source = BrowserExtensionInstallationSource.localPackage(
            candidate.source
        )
        var didLoadNewContext = false
        do {
            let compatibilityPackage = try prepareCompatibilityPackage(
                package,
                extensionID: extensionID,
                source: source,
                spaceID: space.id,
                requestedPermissions: candidate.requestedPermissions
            )
            if let existingContext = runtime.loadedContext(
                extensionID: extensionID,
                in: space.id
            ) {
                try runtime.controller(for: space).unload(existingContext)
                runtime.releaseContext(extensionID: extensionID, in: space.id)
            }
            let context = try await runtime.loadExtension(
                at: compatibilityPackage?.resourceURL
                    ?? package.resourceURL,
                extensionID: extensionID,
                in: space,
                unsupportedAPIs: Set(previous?.unsupportedAPIs ?? []),
                permissionSnapshot: previous?.permissionSnapshot
                    ?? BrowserExtensionInstallationPermissionPolicy
                    .reviewedRequiredAccess(
                        permissions: candidate.requestedPermissions,
                        hosts: candidate.requestedHosts
                    ),
                persistsRuntimeSummary: false,
                source: source
            )
            didLoadNewContext = true
            var runtimeSummary = runtime.summary(
                for: context,
                extensionID: extensionID,
                isEnabled: true
            )
            runtimeSummary.sourceDisplayName =
                candidate.format.sourceDisplayName
            runtimeSummary.iconPayload = candidate.iconPayload
            runtimeSummary.hasOptionsPage = candidate.hasOptionsPage
            runtimeSummary.hasCommands = candidate.hasCommands
            runtimeSummary.isPinned = previous?.isPinned == true

            let now = Date.now
            let installation = BrowserExtensionInstallation(
                id: extensionID,
                spaceID: space.id,
                packageName: package.packageName,
                source: source,
                displayName: runtimeSummary.displayName,
                version: runtimeSummary.version,
                requestedPermissions: runtimeSummary.requestedPermissions,
                requestedHosts: runtimeSummary.requestedHosts,
                unsupportedAPIs: runtimeSummary.unsupportedAPIs,
                errors: runtimeSummary.errors,
                isEnabled: true,
                permissionSnapshot: runtimeSummary.permissionSnapshot,
                installedAt: previous?.installedAt ?? now,
                modifiedAt: now,
                sourceDisplayName: candidate.format.sourceDisplayName,
                iconData: candidate.iconData,
                hasOptionsPage: candidate.hasOptionsPage,
                hasCommands: candidate.hasCommands,
                isPinned: previous?.isPinned,
                commandShortcutOverrides:
                    previous?.commandShortcutOverrides
            )
            guard persistence.upsert(installation) else {
                throw BrowserExtensionControllerPoolError
                    .invalidInstallationRecord
            }
            persistence.updateSummary(runtimeSummary, in: space.id)
            persistence.removeReplacedPackageIfNeeded(
                previous,
                retaining: package.packageName,
                in: space.id
            )
            if let compatibilityPackage {
                runtime.retainRuntimeResourceAccess(
                    compatibilityPackage,
                    extensionID: extensionID,
                    in: space.id
                )
            }
            return runtimeSummary
        } catch {
            if didLoadNewContext,
                let context = runtime.loadedContext(
                    extensionID: extensionID,
                    in: space.id
                )
            {
                try? runtime.controller(for: space).unload(context)
                runtime.releaseContext(extensionID: extensionID, in: space.id)
            }
            persistence.discard(package)
            await restorePreviousInstallation(
                previous,
                extensionID: extensionID,
                in: space
            )
            throw error
        }
    }

    private static var mozillaAddonsDisplayName: String { "Firefox Add-ons" }

    private func prepareCompatibilityPackage(
        _ package: BrowserExtensionPackage,
        extensionID: String,
        source: BrowserExtensionInstallationSource,
        spaceID: SpaceID,
        requestedPermissions: [String]
    ) throws -> BrowserWebExtensionPreparedPackage? {
        try BrowserWebExtensionCompatibilityPackagePreparer()
            .prepareStoredResource(
                package.resourceURL,
                requestedPermissions: requestedPermissions,
                runtimeIdentity:
                    BrowserExtensionRuntimeIdentifierPolicy
                    .identity(
                        extensionID: extensionID,
                        source: source,
                        spaceID: spaceID
                    )
            )
    }

    private func restorePreviousInstallation(
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
