import Foundation

/// Projection of one core download record. The core ledger owns every
/// transition; this value only carries what presentation reads.
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
    var isAcknowledged = false
}

/// Live transfer facts for one row, as the core publishes them. They are not
/// persisted as download history and become inactive once the transfer stops.
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
}

/// One reading from the core progress policy: row telemetry and a progress
/// in [0, 1].
struct BrowserDownloadTransferUpdate: Equatable, Sendable {
    let telemetry: BrowserDownloadTransferTelemetry
    let progress: Double
}
