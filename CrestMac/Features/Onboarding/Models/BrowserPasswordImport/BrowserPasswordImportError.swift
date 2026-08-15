import Foundation

enum BrowserPasswordImportError: LocalizedError, Equatable, Sendable {
    case unsupportedBrowser
    case safeStorageUnavailable
    case unreadableDatabase
    case unsupportedEncryption

    var errorDescription: String? {
        switch self {
        case .unsupportedBrowser:
            "Crest cannot import passwords from this browser yet."
        case .safeStorageUnavailable:
            "Crest could not unlock this browser’s passwords. Allow Keychain access, or turn password import off to continue."
        case .unreadableDatabase:
            "Crest could not read this browser’s password database. Close the source browser and try again."
        case .unsupportedEncryption:
            "This browser uses a password format Crest cannot import safely."
        }
    }
}
