import Foundation

enum BrowserTabMigrationError: LocalizedError, Equatable, Sendable {
    case fileTooLarge
    case invalidContents
    case encryptedChromiumSession
    case noImportableTabs
    case resourceLimitExceeded

    var errorDescriptionResource: LocalizedStringResource {
        switch self {
        case .fileTooLarge:
            "This session file is larger than Crest’s 512 MB import limit."
        case .invalidContents:
            "Crest could not recognize this browser’s tab-session data."
        case .encryptedChromiumSession:
            "This Chromium session is profile-encrypted and cannot be safely imported outside its source browser."
        case .noImportableTabs:
            "This session has no HTTP or HTTPS tabs Crest can import."
        case .resourceLimitExceeded:
            "This session exceeds Crest’s tab, window, text, or decompression limits."
        }
    }

    var errorDescription: String? {
        String(localized: errorDescriptionResource)
    }
}
