import Foundation

/// A rejection reads as what its rule tells the person, where the rule says
/// anything, so an error view shows the core's refusal in the same words.
extension Rejection: LocalizedError {
    // MARK: - Static Variables

    /// What the person is told of a refused action whose rule says nothing
    /// of its own.
    static let unexplained: LocalizedStringResource = "These items cannot be placed here. Choose another destination."

    // MARK: - Variables

    var errorDescription: String? {
        message.map { String(localized: $0) }
    }

    /// What the person is told: the rule's own words, or `unexplained`.
    var explanation: String {
        String(localized: message ?? Self.unexplained)
    }
}
