import Foundation

// MARK: - Types

/// What a login keeps beside its password, as a list says it without reading
/// the secrets: whether it has notes and whether it makes one-time codes.
struct BrowserCredentialExtrasSummary: Codable, Equatable, Sendable {
    let hasNotes: Bool
    let hasCode: Bool
}

/// What a login keeps beside its password: the person's notes, and the setup
/// key of its one-time code as an `otpauth` link. Both are secrets, kept in a
/// companion item that older builds never read. Like `BrowserCredential`, it is
/// deliberately not `Codable`, so it never reaches the session or a record by
/// accident.
struct BrowserCredentialExtras: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    // MARK: - Static Variables

    /// The longest notes a login keeps.
    static let maximumNotesLength = 10_000

    /// A login with neither notes nor a code.
    static let empty = BrowserCredentialExtras(notes: "", codeLink: nil)

    // MARK: - Variables

    var notes: String
    var codeLink: String?

    /// Whether the login keeps nothing beside its password, so its companion
    /// item can go.
    var isEmpty: Bool { notes.isEmpty && codeLink == nil }

    var summary: BrowserCredentialExtrasSummary {
        BrowserCredentialExtrasSummary(hasNotes: !notes.isEmpty, hasCode: codeLink != nil)
    }

    var description: String {
        "BrowserCredentialExtras(notes: <redacted>, codeLink: \(codeLink == nil ? "nil" : "<redacted>"))"
    }

    var debugDescription: String { description }
}

/// What the person changed about a saved login in Settings. `password` and
/// `extras` are nil when they stay as saved; `sites` are the sites the login
/// names beside the one it was saved for.
struct BrowserCredentialEdit: Sendable, CustomStringConvertible {
    var title: String
    var username: String
    var sites: [CredentialOrigin]
    var password: String?
    var extras: BrowserCredentialExtras?

    var description: String {
        "BrowserCredentialEdit(username: \(username), sites: \(sites.count), password: <redacted>, extras: <redacted>)"
    }
}
