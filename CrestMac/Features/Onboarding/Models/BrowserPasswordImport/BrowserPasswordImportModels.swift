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

/// Why passwords could not be read from a browser, as the person is told.
struct BrowserPasswordImportError: LocalizedError, Equatable, Sendable {
    // MARK: - Static Variables

    static let unsupportedBrowser = BrowserPasswordImportError(
        name: "unsupportedBrowser", message: "Crest cannot import passwords from this browser yet.")
    static let safeStorageUnavailable = BrowserPasswordImportError(
        name: "safeStorageUnavailable",
        message:
            "Crest could not unlock this browser’s passwords. Allow Keychain access, or turn password import off to continue."
    )
    static let unreadableDatabase = BrowserPasswordImportError(
        name: "unreadableDatabase",
        message: "Crest could not read this browser’s password database. Close the source browser and try again.")
    static let unsupportedEncryption = BrowserPasswordImportError(
        name: "unsupportedEncryption", message: "This browser uses a password format Crest cannot import safely.")

    // MARK: - Variables

    let name: String
    let message: LocalizedStringResource

    var errorDescription: String? { String(localized: message) }

    // MARK: - Initializers

    private init(name: String, message: LocalizedStringResource) {
        self.name = name
        self.message = message
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserPasswordImportError, rhs: BrowserPasswordImportError) -> Bool {
        lhs.name == rhs.name
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
