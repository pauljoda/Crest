import Foundation

/// Why unlocking a Space did not finish, and what the person is told.
struct BrowserSpaceAccessFailure: Equatable, Sendable {
    // MARK: - Static Variables

    static let authenticationDenied = BrowserSpaceAccessFailure(
        name: "authenticationDenied", message: "Authentication failed. Try again.")
    static let authenticationUnavailable = BrowserSpaceAccessFailure(
        name: "authenticationUnavailable", message: "Authentication didn’t complete. Try again.")

    // MARK: - Variables

    let name: String
    let message: LocalizedStringResource

    // MARK: - Initializers

    private init(name: String, message: LocalizedStringResource) {
        self.name = name
        self.message = message
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSpaceAccessFailure, rhs: BrowserSpaceAccessFailure) -> Bool {
        lhs.name == rhs.name
    }
}
