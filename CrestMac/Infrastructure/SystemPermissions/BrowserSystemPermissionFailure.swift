import Foundation

/// Why asking macOS for a permission could not finish, as the permission's row
/// explains it.
struct BrowserSystemPermissionFailure: LocalizedError, Equatable, Sendable {
    // MARK: - Static Variables

    /// macOS returned no location decision: its prompt is still open, or it
    /// never showed one.
    static let locationUndecided = BrowserSystemPermissionFailure(
        name: "locationUndecided",
        message: String(
            localized:
                "macOS has not returned a location decision. Respond to its prompt, or open System Settings > Privacy & Security > Location Services to allow Crest."
        ))

    // MARK: - Variables

    let name: String
    let message: String

    var errorDescription: String? { message }

    // MARK: - Initializers

    private init(name: String, message: String) {
        self.name = name
        self.message = message
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSystemPermissionFailure, rhs: BrowserSystemPermissionFailure) -> Bool {
        lhs.name == rhs.name
    }
}
