import SwiftUI

/// What a downloads badge shows for a Space's downloads, wherever it is drawn.
extension Sequence<DownloadState> {
    // MARK: - Variables

    /// The progress a downloads badge shows: the newest live download's, or
    /// nil when none is live.
    var notificationProgress: Double? {
        filter { $0.phase.isLive }
            .max { $0.createdAt < $1.createdAt }
            .map(\.progress)
    }

    // MARK: - Actions - Badge

    /// The colour a downloads badge wears: danger while any download needs
    /// the person's attention, and `accent` otherwise.
    func badgeTint(otherwise accent: Color) -> Color {
        contains { $0.phase.needsAttention } ? CrestColor.danger : accent
    }
}
