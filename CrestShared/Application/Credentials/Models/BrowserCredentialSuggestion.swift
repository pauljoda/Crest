import Foundation

// MARK: - Types

/// Every suggestion a prompt shows for a site, and whether it also offers to
/// pair with Apple Passwords.
struct BrowserCredentialOffer: Equatable, Sendable {
    var suggestions: [BrowserCredentialSuggestion]
    var offersApplePasswordsPairing: Bool
    /// The one-time codes offered to a code field, which shows nothing else.
    var codes: [BrowserOneTimeCodeSuggestion] = []
    /// Whether the list ends with the row that opens Apple's Passwords app on
    /// the site: Apple Passwords is on for the Space, paired or not.
    var offersOpeningPasswordsApp = false

    var isEmpty: Bool {
        suggestions.isEmpty && codes.isEmpty && !offersApplePasswordsPairing && !offersOpeningPasswordsApp
    }
}

/// A saved account a prompt offers, with the provider that issued it. The
/// provider travels beside the descriptor and never inside it, because the
/// descriptor is what Crest persists and Apple Passwords' rows are not.
struct BrowserCredentialSuggestion: Equatable, Identifiable, Sendable {
    // MARK: - Static Variables

    private static let providerTitles: [CredentialProvider: String] = [
        .crestPasswords: String(localized: "Crest Passwords"),
        .applePasswords: String(localized: "Apple Passwords"),
    ]

    // MARK: - Variables

    let descriptor: CredentialDescriptor
    let provider: CredentialProvider

    var id: UUID { descriptor.id }
    var providerTitle: String { Self.providerTitles[provider] ?? provider.name }
}
