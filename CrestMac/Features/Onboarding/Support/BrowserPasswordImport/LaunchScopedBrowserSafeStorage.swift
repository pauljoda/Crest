struct LaunchScopedBrowserSafeStorage: BrowserSafeStorageSecretProviding {
    private let safeStorage: (any BrowserSafeStorageSecretProviding)?

    init(
        launchEnvironment: BrowserLaunchEnvironment = .current,
        systemStorage: () -> any BrowserSafeStorageSecretProviding = {
            SecurityBrowserSafeStorage()
        }
    ) {
        if BrowserLaunchIsolationPolicy.requiresIsolation(launchEnvironment) {
            safeStorage = nil
        } else {
            safeStorage = systemStorage()
        }
    }

    func secret(for application: BrowserImportApplication) throws -> String {
        guard let safeStorage else {
            throw BrowserPasswordImportError.safeStorageUnavailable
        }
        return try safeStorage.secret(for: application)
    }
}
