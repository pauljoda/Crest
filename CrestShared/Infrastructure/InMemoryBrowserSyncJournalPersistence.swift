import Foundation

final class InMemoryBrowserSyncJournalPersistence: BrowserSyncJournalPersisting {
    private(set) var journal: BrowserSyncJournal?

    func load() throws -> BrowserSyncJournal? {
        journal
    }

    func save(_ journal: BrowserSyncJournal) throws {
        self.journal = journal
    }
}
