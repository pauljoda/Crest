import Foundation

/// A launch that could not open the core's session file, and what the recovery
/// screen may offer for it.
struct BrowserSessionStartupFailure: Error {
    /// The directory the core keeps its session in, when the launch got as far
    /// as naming one.
    let storageDirectory: URL?
    let underlying: Error

    /// The file was written by a newer release, which a restore must not undo.
    var requiresNewerApp: Bool {
        if case .storageFromNewerApp = underlying as? Rejection { return true }
        return false
    }

    var checkpointDate: Date? {
        guard !requiresNewerApp, let storageDirectory else { return nil }
        return try? BrowserSessionRecovery.checkpointURL(in: storageDirectory)
            .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Puts the recovery checkpoint in place of the session file. The core
    /// keeps the failed file and its sidecars beside it, and throws the
    /// rejection naming why it could not.
    func restore() throws {
        guard !requiresNewerApp, let storageDirectory else { throw BrowserSessionRecovery.RecoveryError.unavailable }
        try CrestCore.restoreRecoveryCheckpoint(
            configuration: AppConfiguration(storageDirectory: storageDirectory.path))
    }
}

/// What the recovery screen and the cloud transport read beside the core's
/// session file. The core writes the file, its recovery checkpoint and the
/// cloud-recovery marker; this side only reports the checkpoint's age and
/// consumes the marker once the transport has opted into a full pull.
enum BrowserSessionRecovery {
    enum RecoveryError: Error {
        /// Nothing may be restored over this file.
        case unavailable
    }

    private static let checkpointName = "session.recovery.sqlite"
    private static let cloudMarkerName = "session.sqlite.cloud-recovery"

    static func checkpointURL(in directory: URL) -> URL { directory.appendingPathComponent(checkpointName) }
    static func cloudMarker(in directory: URL) -> URL { directory.appendingPathComponent(cloudMarkerName) }

    /// While the core's marker is beside the file, the cloud transport's cursor
    /// cannot describe the local journal: the file holds a seed standing in for
    /// an unreadable installed session, or a restored journal. The cursor is
    /// reset to a full pull first, and only then is the marker removed.
    static func prepareCloudRecovery(in directory: URL, environment: BrowserLaunchEnvironment) throws {
        let marker = cloudMarker(in: directory)
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let persistence: any BrowserCloudSyncStatePersisting
        if environment.requiresIsolation {
            guard let configuration = BrowserCloudSyncConfiguration.configured()?.isolated(for: environment),
                let id = environment.persistentIsolationID,
                let isolated = FileBrowserCloudSyncStatePersistence.isolated(
                    localProfileID: id, configuration: configuration)
            else { return }
            persistence = isolated
        } else {
            persistence =
                FileBrowserCloudSyncStatePersistence.production()
                ?? UserDefaultsBrowserCloudSyncStatePersistence()
        }
        try resetCloudCursor(persistence)
        try FileManager.default.removeItem(at: marker)
    }

    static func resetCloudCursor(_ persistence: any BrowserCloudSyncStatePersisting) throws {
        var state = try persistence.load() ?? BrowserCloudSyncState()
        state.engineStateSerialization = nil
        state.systemFields = BrowserCloudRecordSystemFields()
        state.conflictResolution = nil
        state.requiresFullPull = true
        // Account confirmation remains mandatory if the account changed.
        try persistence.save(state)
    }
}
