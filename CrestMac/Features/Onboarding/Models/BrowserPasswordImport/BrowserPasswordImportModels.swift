import Foundation

struct BrowserEncryptedPasswordRecord {
    let origin: CredentialOrigin
    let username: String
    let encryptedPassword: Data
}

struct BrowserImportedPassword:
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let sourceApplication: ImportSource
    let sourceProfileID: String
    let sourceProfileName: String
    let origin: CredentialOrigin
    let username: String
    let password: String

    var description: String {
        "BrowserImportedPassword(profile: \(sourceProfileID), origin: \(origin), username: <redacted>, password: <redacted>)"
    }

    var debugDescription: String { description }
}

struct BrowserPasswordImportCandidate: Sendable {
    let sourceApplication: ImportSource
    let sourceProfileID: String
    let sourceProfileName: String
    let origin: CredentialOrigin
}

enum BrowserPasswordImportError: LocalizedError, Equatable, Sendable {
    case unsupportedBrowser
    case safeStorageUnavailable
    case unreadableDatabase
    case unsupportedEncryption

    var errorDescription: String? {
        switch self {
        case .unsupportedBrowser:
            String(localized: "Crest cannot import passwords from this browser yet.")
        case .safeStorageUnavailable:
            String(
                localized:
                    "Crest could not unlock this browser’s passwords. Allow Keychain access, or turn password import off to continue."
            )
        case .unreadableDatabase:
            String(
                localized:
                    "Crest could not read this browser’s password database. Close the source browser and try again.")
        case .unsupportedEncryption:
            String(localized: "This browser uses a password format Crest cannot import safely.")
        }
    }
}

/// How many passwords an import saved, left out as the review chose, and
/// could not save.
struct BrowserPasswordImportResult: Equatable, Sendable {
    let importedCount: Int
    let skippedCount: Int
    let unsavedCount: Int

    static let empty = BrowserPasswordImportResult(
        importedCount: 0,
        skippedCount: 0,
        unsavedCount: 0
    )
}
