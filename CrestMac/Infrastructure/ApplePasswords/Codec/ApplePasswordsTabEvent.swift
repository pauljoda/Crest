import Foundation

/// What happened to a tab, as the helper is told: numbered in a tab event's `event`.
struct ApplePasswordsTabEvent: Hashable, Sendable, Encodable {
    // MARK: - Static Variables

    /// The tab was closed.
    static let closed = ApplePasswordsTabEvent(number: 0)
    /// The tab was selected, or the window showing it came to the front.
    static let activated = ApplePasswordsTabEvent(number: 1)

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
