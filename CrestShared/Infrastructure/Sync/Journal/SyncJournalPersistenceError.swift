import Foundation

enum BrowserSyncJournalPersistenceError: Error, Equatable {
    case encodingFailed
    case decodingFailed
}
