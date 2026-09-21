import Foundation
import Darwin

struct BrowserSessionStartupFailure: Error {
    let storeURL: URL?
    let underlying: Error

    var requiresNewerApp: Bool {
        #if CREST_CORE_BACKED
        if case BrowserTransactionalSessionPersistence.StorageError.unsupportedVersion = underlying { return true }
        if case BrowserSyncError.unsupportedSchema = underlying { return true }
        #endif
        return false
    }

    var checkpointDate: Date? {
        guard !requiresNewerApp, let storeURL else { return nil }
        return try? BrowserSessionRecovery.checkpointURL(for: storeURL)
            .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    func restore() throws {
        #if CREST_CORE_BACKED
        guard !requiresNewerApp, let storeURL else {
            throw BrowserTransactionalSessionPersistence.StorageError.invalidCheckpoint
        }
        try BrowserSessionRecovery.restore(storeURL)
        #endif
    }
}

/// Filesystem recovery runs before any session, engine pages or sync transport
/// exist. Originals and the last startup checkpoint are retained after restore.
enum BrowserSessionRecovery {
    static func checkpointURL(for url: URL) -> URL { url.deletingPathExtension().appendingPathExtension("recovery.sqlite") }
    static func restoreMarker(for url: URL) -> URL { url.appendingPathExtension("restore-pending") }
    static func cloudMarker(for url: URL) -> URL { url.appendingPathExtension("cloud-recovery") }

    static func removeTemporaryDatabase(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }

    static func atomicReplace(_ source: URL, destination: URL) throws {
        guard rename(source.path, destination.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    #if CREST_CORE_BACKED
    static func restore(_ url: URL) throws {
        let files = FileManager.default
        let directory = url.deletingLastPathComponent()
        let candidate = directory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { removeTemporaryDatabase(candidate) }
        try files.copyItem(at: checkpointURL(for: url), to: candidate)
        // Decode every session part and rotate only the journal's local identity.
        // Never touch the failed database unless this candidate is usable.
        try prepareCandidate(candidate)
        let preserved = directory.appendingPathComponent("Recovery-" + UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: preserved, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            if files.fileExists(atPath: source.path) {
                try files.copyItem(at: source, to: preserved.appendingPathComponent(source.lastPathComponent))
            }
        }
        try Data(preserved.path.utf8).write(to: restoreMarker(for: url), options: .atomic)
        // Keep this marker until the matching cloud transport has durably opted
        // into a full merge. Its newer cursor cannot describe the older journal.
        try Data().write(to: cloudMarker(for: url), options: .atomic)
        for suffix in ["-wal", "-shm"] where files.fileExists(atPath: url.path + suffix) {
            try files.removeItem(atPath: url.path + suffix)
        }
        try atomicReplace(candidate, destination: url)
        try files.removeItem(at: restoreMarker(for: url))
    }

    private static func prepareCandidate(_ url: URL) throws {
        let storage = try BrowserTransactionalSessionPersistence(url: url, favicons: InMemoryBrowserFaviconStore())
        guard storage.load() != nil, let journal = try storage.journalPersistence.load() else {
            throw BrowserTransactionalSessionPersistence.StorageError.incompleteSession
        }
        try storage.journalPersistence.save(journal.recoveredForNewDevice())
    }

    static func prepareCloudRecovery(storeURL: URL, environment: BrowserLaunchEnvironment) throws {
        let marker = cloudMarker(for: storeURL)
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let persistence: any BrowserCloudSyncStatePersisting
        if BrowserLaunchIsolationPolicy.requiresIsolation(environment) {
            guard let configuration = BrowserCloudSyncConfiguration.configured()?.isolated(for: environment),
                let id = environment.persistentIsolationID,
                let isolated = FileBrowserCloudSyncStatePersistence.isolated(localProfileID: id, configuration: configuration)
            else { return }
            persistence = isolated
        } else {
            persistence = FileBrowserCloudSyncStatePersistence.production()
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
    #endif
}
