import Foundation
import WebKit

extension BrowserExtensionControllerPool {
    func loadExtension(
        at resourceBaseURL: URL,
        extensionID: String,
        in space: BrowserSpace,
        unsupportedAPIs: Set<String> = [],
        source: BrowserExtensionInstallationSource? = nil,
        permissionSnapshot: BrowserExtensionPermissionSnapshot = .empty
    ) async throws -> WKWebExtensionContext {
        try await installationController.loadExtension(
            at: resourceBaseURL,
            extensionID: extensionID,
            in: space,
            unsupportedAPIs: unsupportedAPIs,
            source: source,
            permissionSnapshot: permissionSnapshot
        )
    }

    @discardableResult
    func loadUnpackedExtension(
        from sourceURL: URL,
        in space: BrowserSpace
    ) async throws -> BrowserExtensionSummary {
        try await installationController.loadUnpackedExtension(
            from: sourceURL,
            in: space
        )
    }

    func removeExtension(
        extensionID: String,
        from space: BrowserSpace
    ) async throws {
        try await installationController.removeExtension(
            extensionID: extensionID,
            from: space
        )
    }

    func deleteData(
        for space: BrowserSpace
    ) async throws -> BrowserSpaceDataReleaseProbe {
        try await installationController.deleteData(for: space)
    }
}
