import Foundation

/// Stores the cloud-sync state as a file rather than a `UserDefaults` value.
///
/// The state carries archived `CKRecord` system fields for every record in the
/// zone — megabytes once a browsing history has accumulated — and CFPreferences
/// refuses single values of 4MB or more, at which point the engine's bookkeeping
/// stops persisting and sync degenerates into refetch-and-conflict loops. A file
/// has no such cap, and rewriting one file is far cheaper than rewriting the
/// whole preferences domain on every sync event.
///
/// The first `load()` migrates a blob left in `UserDefaults` by earlier builds
/// and deletes the old key, which also shrinks the preferences plist back to a
/// sane size.
final class FileBrowserCloudSyncStatePersistence: BrowserCloudSyncStatePersisting, @unchecked Sendable {
    static let directoryName = "CloudSync"
    static let fileName = "state.v1.json"

    private let fileURL: URL
    private let migrationDefaults: UserDefaults?
    private let migrationKey: String
    private let fileManager = FileManager.default
    private let lock = NSLock()

    /// The production store, or nil when this process has no usable Application
    /// Support directory — the caller falls back to the defaults-backed store so
    /// sync still works, cap and all, rather than failing the launch.
    static func production(
        migrationDefaults: UserDefaults = .standard
    ) -> FileBrowserCloudSyncStatePersistence? {
        guard
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else { return nil }
        let directory =
            applicationSupport
            .appendingPathComponent(
                ProductIdentity.storageDirectoryName,
                isDirectory: true
            )
            .appendingPathComponent(directoryName, isDirectory: true)
        return FileBrowserCloudSyncStatePersistence(
            fileURL: directory.appendingPathComponent(Self.fileName),
            migrationDefaults: migrationDefaults
        )
    }

    init(
        fileURL: URL,
        migrationDefaults: UserDefaults? = nil,
        migrationKey: String = UserDefaultsBrowserCloudSyncStatePersistence.defaultKey
    ) {
        self.fileURL = fileURL
        self.migrationDefaults = migrationDefaults
        self.migrationKey = migrationKey
    }

    func load() throws -> BrowserCloudSyncState? {
        lock.lock()
        defer { lock.unlock() }
        if let data = try? Data(contentsOf: fileURL) {
            return try decode(data)
        }
        guard let legacyData = migrationDefaults?.data(forKey: migrationKey)
        else { return nil }
        let state = try decode(legacyData)
        try write(state)
        // Only after the file write survives: a failed migration must leave the
        // blob where the next launch can retry it.
        migrationDefaults?.removeObject(forKey: migrationKey)
        return state
    }

    func save(_ state: BrowserCloudSyncState) throws {
        lock.lock()
        defer { lock.unlock() }
        try write(state)
    }

    private func decode(_ data: Data) throws -> BrowserCloudSyncState {
        do {
            return try JSONDecoder().decode(BrowserCloudSyncState.self, from: data)
        } catch {
            throw BrowserCloudSyncStatePersistenceError.decodingFailed
        }
    }

    private func write(_ state: BrowserCloudSyncState) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(state)
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw BrowserCloudSyncStatePersistenceError.encodingFailed
        }
    }
}
