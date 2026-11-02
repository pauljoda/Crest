import SwiftUI

/// The notices a group change shows on iPhone and iPad, which have no notice
/// capsule: Space settings shows the latest one under its Spaces until the
/// person leaves it.
@MainActor
@Observable
final class BrowserSpaceGroupNotices {
    // MARK: - Types

    struct Notice: Equatable {
        let message: String
        let systemImage: String
    }

    // MARK: - Static Variables

    static let shared = BrowserSpaceGroupNotices()

    // MARK: - Variables

    private(set) var current: Notice?

    // MARK: - Actions - Showing

    /// A Space joined a group: the first group on this device reminds the
    /// person to update Crest on their other devices.
    static func formed() {
        guard BrowserSpaceGroupUpdateNotice.takeIfDue() else { return }
        shared.current = Notice(message: BrowserSpaceGroupUpdateNotice.message, systemImage: "arrow.down.circle")
    }

    /// The change could not run: `reason` says why.
    static func failed(_ reason: String) {
        shared.current = Notice(message: reason, systemImage: "exclamationmark.triangle.fill")
    }

    // MARK: - Mutators

    func dismiss() {
        current = nil
    }
}
