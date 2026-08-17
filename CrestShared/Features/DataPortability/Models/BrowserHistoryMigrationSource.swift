import Foundation

enum BrowserHistoryMigrationSource: String, CaseIterable, Identifiable, Sendable {
    case safari
    case chrome
    case firefox
    case arc

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .safari: "Safari"
        case .chrome: "Chrome or Chromium"
        case .firefox: "Firefox"
        case .arc: "Arc"
        }
    }

    var importedSpaceName: LocalizedStringResource {
        switch self {
        case .safari: "Imported History from Safari"
        case .chrome: "Imported History from Chrome"
        case .firefox: "Imported History from Firefox"
        case .arc: "Imported History from Arc"
        }
    }

    var symbol: String {
        switch self {
        case .safari: "safari"
        case .chrome: "globe"
        case .firefox: "flame"
        case .arc: "sidebar.left"
        }
    }

    var accent: SpaceAccent {
        switch self {
        case .safari: .teal
        case .chrome: .orange
        case .firefox: .rose
        case .arc: .indigo
        }
    }

    var databaseFilename: String {
        switch self {
        case .safari: "History.db"
        case .chrome, .arc: "History"
        case .firefox: "places.sqlite"
        }
    }
}

struct BrowserHistorySQLiteRecord: Sendable {
    let url: String
    let title: String
    let firstVisit: Double
    let lastVisit: Double
    let visitCount: Int
}

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
