import Foundation

/// Opens the release page of the update a card presents, in a new tab of the
/// window it shows in. Rebuilding a view keeps the same action while the
/// window it opens in stays the same.
struct BrowserSoftwareUpdateReleasePageAction: Equatable {
    // MARK: - Variables

    private let ownerID: ObjectIdentifier
    private let perform: @MainActor (String) -> Void

    // MARK: - Initializers

    init(owner: AnyObject, perform: @escaping @MainActor (_ version: String) -> Void) {
        ownerID = ObjectIdentifier(owner)
        self.perform = perform
    }

    // MARK: - Actions

    /// Opens the page of the update to `version`.
    @MainActor func callAsFunction(version: String) { perform(version) }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.ownerID == rhs.ownerID }
}
