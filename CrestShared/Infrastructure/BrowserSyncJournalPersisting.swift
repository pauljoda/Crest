import Foundation

protocol BrowserSyncJournalPersisting: AnyObject {
    func load() throws -> BrowserSyncJournal?
    func save(_ journal: BrowserSyncJournal) throws
}
