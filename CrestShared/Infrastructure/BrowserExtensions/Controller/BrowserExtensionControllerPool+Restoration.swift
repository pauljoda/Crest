extension BrowserExtensionControllerPool {
    func restoreEnabledExtensions(in spaces: [BrowserSpace]) async {
        await restorationController.restoreEnabledExtensions(in: spaces)
    }

    func setExtensionEnabled(
        _ enabled: Bool,
        extensionID: String,
        in space: BrowserSpace
    ) async throws {
        try await restorationController.setExtensionEnabled(
            enabled,
            extensionID: extensionID,
            in: space
        )
    }
}
