import Foundation

/// Where a one-time code comes from. A generated code changes every few
/// seconds, so the helper is asked for the current one after the pick. Any
/// other source (a message, a mail) delivered its code with the list, and that
/// code is filled as it is.
struct ApplePasswordsOneTimeCodeSource: Hashable, Sendable {
    // MARK: - Static Variables

    /// The helper's spelling of a generated code.
    private static let generatedName = "totp"

    static let generated = ApplePasswordsOneTimeCodeSource(asksForCurrentCode: true)
    static let delivered = ApplePasswordsOneTimeCodeSource(asksForCurrentCode: false)

    // MARK: - Variables

    /// Whether the code to fill is read from the helper after the pick.
    let asksForCurrentCode: Bool

    // MARK: - Initializers

    private init(asksForCurrentCode: Bool) {
        self.asksForCurrentCode = asksForCurrentCode
    }

    /// The source a reply names; a name Crest does not know is a delivered code.
    static func named(_ name: String?) -> ApplePasswordsOneTimeCodeSource {
        name == generatedName ? .generated : .delivered
    }
}
