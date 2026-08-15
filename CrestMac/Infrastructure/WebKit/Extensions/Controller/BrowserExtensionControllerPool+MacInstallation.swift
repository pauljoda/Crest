extension BrowserExtensionControllerPool {
    @discardableResult
    func installSafariWebExtension(
        _ candidate: BrowserSafariWebExtensionCandidate,
        in space: BrowserSpace
    ) async throws -> BrowserExtensionSummary {
        try await installationController.installSafariWebExtension(
            candidate,
            in: space
        )
    }

    @discardableResult
    func installChromeWebStoreExtension(
        _ candidate: BrowserChromeWebStoreCandidate,
        in space: BrowserSpace
    ) async throws -> BrowserExtensionSummary {
        try await installationController.installChromeWebStoreExtension(
            candidate,
            in: space
        )
    }

    @discardableResult
    func installMozillaAddonsExtension(
        _ candidate: BrowserMozillaAddonsCandidate,
        in space: BrowserSpace
    ) async throws -> BrowserExtensionSummary {
        try await installationController.installMozillaAddonsExtension(
            candidate,
            in: space
        )
    }
}
