import Foundation

final class UserDefaultsBrowserCloudSyncStatePersistence: BrowserCloudSyncStatePersisting, @unchecked Sendable {
    static let defaultKey = "crest.cloud-sync.state.v1"

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard, key: String = defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func load() throws -> BrowserCloudSyncState? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(BrowserCloudSyncState.self, from: data)
        } catch {
            throw BrowserCloudSyncStatePersistenceError.decodingFailed
        }
    }

    func save(_ state: BrowserCloudSyncState) throws {
        lock.lock()
        defer { lock.unlock() }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            defaults.set(try encoder.encode(state), forKey: key)
        } catch {
            throw BrowserCloudSyncStatePersistenceError.encodingFailed
        }
    }
}
