import Foundation

extension DownloadState {
    /// How far the transfer has come, or nil while that cannot be told:
    /// before the download moves any bytes, and while its engine knows no
    /// total size, when the core's progress would stay at zero.
    var knownProgress: Double? {
        guard phase.isTransferring, telemetry.totalBytes != nil || progress > 0 else { return nil }
        return min(max(progress, 0), 1)
    }
}
