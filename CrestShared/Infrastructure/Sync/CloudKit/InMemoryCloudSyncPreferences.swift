@MainActor
final class InMemoryBrowserCloudSyncPreferences: BrowserCloudSyncPreferences {
    private var isEnabled: Bool?

    init(isEnabled: Bool? = true) {
        self.isEnabled = isEnabled
    }

    func loadIsEnabled() -> Bool? {
        isEnabled
    }

    func saveIsEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func requiresAccountConfirmation() throws -> Bool {
        false
    }

    func resetTransportState() throws {}

    func saveConflictResolution(
        _: BrowserCloudConflictResolution?
    ) throws {}
}
