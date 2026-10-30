import Foundation

extension Sequence<DownloadState> {
    // MARK: - Variables

    /// The download a downloads control speaks for: the newest live one, or
    /// nil when none is live.
    var newestLiveDownload: DownloadState? {
        filter { $0.phase.isLive }
            .max { $0.createdAt < $1.createdAt }
    }

    /// The progress a downloads badge shows: the newest live download's, or
    /// nil when none is live.
    var notificationProgress: Double? {
        newestLiveDownload.map(\.progress)
    }
}
