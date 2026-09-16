import Foundation

extension BrowserExtensionInstallationController {
    /// Copies package resources and consent, never the extension's website data.
    func copyExtension(
        extensionID: String, from sourceSpace: SpaceID, to space: BrowserSpace,
        validateAccess: () throws -> Void
    ) async throws -> BrowserExtensionSummary {
        try validateAccess()
        guard sourceSpace != space.id,
            persistence.installation(extensionID: extensionID, in: space.id) == nil,
            let source = persistence.installation(extensionID: extensionID, in: sourceSpace)
        else { throw BrowserExtensionControllerPoolError.invalidInstallationRecord }

        let client = BrowserExtensionServiceClientID.scoped(extensionID: extensionID, spaceID: space.id)
        guard pendingCopies.insert(client).inserted else {
            throw BrowserExtensionControllerPoolError.invalidInstallationRecord
        }
        defer { pendingCopies.remove(client) }
        let package: BrowserExtensionPackage?
        if case .safariWebExtension = source.source {
            package = nil
        } else {
            package = try await persistence.stageCopy(of: source, in: space.id)
        }
        let now = Date.now
        let copy = BrowserExtensionInstallation(
            id: source.id, spaceID: space.id, packageName: package?.packageName ?? source.packageName,
            source: source.source, displayName: source.displayName, version: source.version,
            requestedPermissions: source.requestedPermissions, requestedHosts: source.requestedHosts,
            unsupportedAPIs: [], errors: [], isEnabled: true, permissionSnapshot: source.permissionSnapshot,
            installedAt: now, modifiedAt: now, sourceDisplayName: source.sourceDisplayName,
            iconData: source.iconData, hasOptionsPage: source.hasOptionsPage, hasSidebar: source.hasSidebar,
            hasCommands: source.hasCommands)
        do {
            try validateAccess()
            guard persistence.installation(extensionID: copy.id, in: space.id) == nil else {
                throw BrowserExtensionControllerPoolError.invalidInstallationRecord
            }
        } catch {
            if let package { persistence.discard(package) }
            throw error
        }
        let lifecycle = prepareContextMenuInstallLifecycle(
            previous: nil, extensionID: copy.id, spaceID: space.id, requestedPermissions: copy.requestedPermissions)
        var didLoadContext = false
        do {
            let context = try await runtime.loadInstallation(copy, in: space, validateAccess: validateAccess)
            didLoadContext = true
            _ = await runtime.prepareBackgroundForInitialContentScriptTraffic(context)
            try validateAccess()
            guard persistence.upsert(copy) else {
                throw BrowserExtensionControllerPoolError.invalidInstallationRecord
            }
            let summary = runtime.summary(for: context, installation: copy)
            persistence.updateSummary(summary, in: space.id)
            return summary
        } catch {
            cancelContextMenuInstallLifecycle(lifecycle)
            if didLoadContext, let context = runtime.loadedContext(extensionID: copy.id, in: space.id) {
                try? runtime.controller(for: space).unload(context)
                runtime.releaseContext(extensionID: copy.id, in: space.id)
            }
            if didLoadContext { persistence.removeSummary(extensionID: copy.id, in: space.id) }
            if let package { persistence.discard(package) }
            throw error
        }
    }
}
