import Foundation

final class UserDefaultsBrowserSyncJournalPersistence: BrowserSyncJournalPersisting {
    // SwiftUI observes standard defaults synchronously for @AppStorage. Sync stages run on a
    // utility executor, so keep journal notifications out of the view update graph.
    private static let dedicatedSuiteName = "com.pauldavis.crest.sync-journal"

    private let defaults: UserDefaults
    private let migrationSource: UserDefaults?
    private let key: String

    convenience init(key: String = "crest.sync.journal.v1") {
        guard let defaults = UserDefaults(suiteName: Self.dedicatedSuiteName) else {
            preconditionFailure("Unable to create the Crest sync journal preferences suite")
        }
        self.init(
            defaults: defaults,
            migrationSource: .standard,
            key: key
        )
    }

    init(defaults: UserDefaults, key: String = "crest.sync.journal.v1") {
        self.defaults = defaults
        migrationSource = nil
        self.key = key
    }

    private init(
        defaults: UserDefaults,
        migrationSource: UserDefaults,
        key: String
    ) {
        self.defaults = defaults
        self.migrationSource = migrationSource
        self.key = key
    }

    func load() throws -> BrowserSyncJournal? {
        if let data = defaults.data(forKey: key) {
            return try decode(data)
        }
        guard let legacyData = migrationSource?.data(forKey: key) else { return nil }
        let journal = try decode(legacyData)
        try save(journal)
        return journal
    }

    private func decode(_ data: Data) throws -> BrowserSyncJournal {
        do {
            return try JSONDecoder().decode(BrowserSyncJournal.self, from: data)
        } catch {
            throw BrowserSyncJournalPersistenceError.decodingFailed
        }
    }

    func save(_ journal: BrowserSyncJournal) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            defaults.set(try encoder.encode(journal), forKey: key)
        } catch {
            throw BrowserSyncJournalPersistenceError.encodingFailed
        }
    }
}
