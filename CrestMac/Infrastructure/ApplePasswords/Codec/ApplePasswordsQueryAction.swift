import Foundation

/// What a query asks the helper to do, numbered in the query body's `ACT`.
struct ApplePasswordsQueryAction: Hashable, Sendable, Encodable {
    // MARK: - Static Variables

    static let update = ApplePasswordsQueryAction(number: 1)
    /// Looks up the entry for one username on one site.
    static let search = ApplePasswordsQueryAction(number: 2)
    static let addNew = ApplePasswordsQueryAction(number: 3)
    /// Adds or updates, as the helper decides, behind its own confirmation alert.
    static let maybeAdd = ApplePasswordsQueryAction(number: 4)
    /// Lists the usernames saved for a site without reading any password.
    static let ghostSearch = ApplePasswordsQueryAction(number: 5)

    // MARK: - Variables

    let number: Int

    // MARK: - Initializers

    private init(number: Int) {
        self.number = number
    }

    // MARK: - Actions - Encoding

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(number)
    }
}
