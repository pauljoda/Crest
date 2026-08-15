import Foundation

enum BrowserHistoryMigrationError: LocalizedError, Equatable, Sendable {
    case fileTooLarge
    case missingFile
    case databaseBusy
    case unrecognizedDatabase
    case noImportableHistory

    var errorDescriptionResource: LocalizedStringResource {
        switch self {
        case .fileTooLarge:
            "This history database is larger than Crest’s 512 MB import limit."
        case .missingFile:
            "Crest could not read this history database."
        case .databaseBusy:
            "Quit the source browser, copy its history database, and import the copy."
        case .unrecognizedDatabase:
            "This file does not match the selected browser’s history format."
        case .noImportableHistory:
            "This database has no HTTP or HTTPS history Crest can import."
        }
    }

    var errorDescription: String? {
        String(localized: errorDescriptionResource)
    }
}
