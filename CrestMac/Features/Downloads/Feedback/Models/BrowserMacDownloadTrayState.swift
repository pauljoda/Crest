import Foundation
import Observation

/// The downloads one Quick Window shows as cards in its corner: each one
/// started on its page, from its start until a moment after it ends or the
/// person sends it away. A card that goes never comes back.
@Observable
@MainActor
final class BrowserMacDownloadTrayState {
    // MARK: - Static Variables

    /// How many cards show at once; an older one gives way to a newer.
    static let maximumVisible = 3
    /// How long a card stays once its download has ended.
    static let settledLifetime: Duration = .seconds(3)

    // MARK: - Variables

    /// The downloads shown, oldest first.
    private(set) var downloadIDs: [UUID] = []

    // MARK: - Actions - Showing

    /// Shows the card of `downloadID`, which just started on the window's
    /// page.
    func show(_ downloadID: UUID) {
        guard !downloadIDs.contains(downloadID) else { return }
        downloadIDs = Array((downloadIDs + [downloadID]).suffix(Self.maximumVisible))
    }

    /// Takes the card of `downloadID` out of the tray.
    func dismiss(_ downloadID: UUID) {
        downloadIDs.removeAll { $0 == downloadID }
    }
}
