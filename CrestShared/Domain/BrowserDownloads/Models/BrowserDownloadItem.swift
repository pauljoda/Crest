import Foundation

struct BrowserDownloadItem: Identifiable, Equatable, Sendable {

    let id: UUID
    let profileID: UUID
    let createdAt: Date
    var filename: String
    var destinationURL: URL?
    var progress: Double
    var telemetry = BrowserDownloadTransferTelemetry.empty
    var state: BrowserDownloadItemState
    var riskAssessment: BrowserDownloadRiskAssessment?
}

/// Live transfer facts reported by WebKit's `Progress` object.
///
/// These values deliberately travel with the in-memory ledger item so every
/// presentation sees one authoritative snapshot. They are not persisted as
/// download history and are made inactive as soon as the transfer stops.
struct BrowserDownloadTransferTelemetry: Equatable, Sendable {
    var bytesReceived: Int64
    var totalBytes: Int64?
    var bytesPerSecond: Double?
    var estimatedTimeRemaining: TimeInterval?
    var isPaused: Bool

    static let empty = BrowserDownloadTransferTelemetry(
        bytesReceived: 0,
        totalBytes: nil,
        bytesPerSecond: nil,
        estimatedTimeRemaining: nil,
        isPaused: false
    )

    var hasKnownTotal: Bool {
        totalBytes != nil
    }

    func stopped(
        finalByteCount: Int64? = nil,
        completed: Bool = false
    ) -> BrowserDownloadTransferTelemetry {
        let finalBytes = max(bytesReceived, finalByteCount ?? 0)
        return BrowserDownloadTransferTelemetry(
            bytesReceived: finalBytes,
            totalBytes: completed ? finalBytes : totalBytes,
            bytesPerSecond: nil,
            estimatedTimeRemaining: nil,
            isPaused: false
        )
    }
}
