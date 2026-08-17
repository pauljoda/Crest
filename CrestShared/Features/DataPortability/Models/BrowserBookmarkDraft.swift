import Foundation

struct BrowserBookmarkDraft: Equatable, Sendable {
    let title: String
    let url: URL
    let folderID: UUID?
    let addedAt: Date
}

struct BrowserBookmarkFolderDraft: Equatable, Sendable {
    let id: UUID
    let title: String
    let parentID: UUID?
}

enum BrowserBookmarkDateEpoch {
    case unixSeconds
    case unixMicroseconds
    case windowsMicroseconds
    case adaptive
}

enum BrowserBookmarkMigrationError: LocalizedError, Equatable, Sendable {
    case fileTooLarge
    case invalidContents
    case noImportableBookmarks
    case resourceLimitExceeded

    var errorDescriptionResource: LocalizedStringResource {
        switch self {
        case .fileTooLarge:
            "This bookmark file is larger than Crest’s 50 MB import limit."
        case .invalidContents:
            "Crest could not recognize this browser’s bookmark data."
        case .noImportableBookmarks:
            "This file does not contain any HTTP or HTTPS bookmarks Crest can import."
        case .resourceLimitExceeded:
            "This bookmark file exceeds Crest’s folder, depth, tab, or Space limits."
        }
    }

    var errorDescription: String? {
        String(localized: errorDescriptionResource)
    }
}
