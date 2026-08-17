@MainActor
protocol BrowserCloudSyncPreferences: AnyObject {
    func loadIsEnabled() -> Bool?
    func saveIsEnabled(_ isEnabled: Bool)
    func requiresAccountConfirmation() throws -> Bool
    func resetTransportState() throws
    func saveConflictResolution(_ resolution: BrowserCloudConflictResolution?) throws
}
