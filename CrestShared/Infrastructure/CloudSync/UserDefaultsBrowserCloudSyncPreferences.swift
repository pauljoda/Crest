import Foundation

@MainActor
final class UserDefaultsBrowserCloudSyncPreferences: BrowserCloudSyncPreferences {
    static let defaultEnabledKey = "crest.cloud-sync.enabled"

    private let defaults: UserDefaults
    private let enabledKey: String
    private let statePersistence: any BrowserCloudSyncStatePersisting

    init(
        defaults: UserDefaults = .standard,
        enabledKey: String = defaultEnabledKey,
        statePersistence: (any BrowserCloudSyncStatePersisting)? = nil
    ) {
        self.defaults = defaults
        self.enabledKey = enabledKey
        self.statePersistence =
            statePersistence
            ?? UserDefaultsBrowserCloudSyncStatePersistence(defaults: defaults)
    }

    func loadIsEnabled() -> Bool? {
        guard defaults.object(forKey: enabledKey) != nil else { return nil }
        return defaults.bool(forKey: enabledKey)
    }

    func saveIsEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: enabledKey)
    }

    func requiresAccountConfirmation() throws -> Bool {
        try statePersistence.load()?.requiresAccountConfirmation == true
    }

    func resetTransportState() throws {
        try statePersistence.save(BrowserCloudSyncState())
    }

    func saveConflictResolution(_ resolution: BrowserCloudConflictResolution?) throws {
        try statePersistence.save(
            BrowserCloudSyncState(conflictResolution: resolution)
        )
    }
}
