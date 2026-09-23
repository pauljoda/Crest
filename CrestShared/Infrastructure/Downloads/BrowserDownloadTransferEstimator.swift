import Foundation

/// One reading from the core progress policy: row telemetry and a progress
/// in [0, 1].
struct BrowserDownloadTransferUpdate: Equatable, Sendable {
    let telemetry: DownloadTelemetry
    let progress: Double
}

/// Per-transfer holder for the core progress policy's state. Rate smoothing,
/// monotonic bytes, total validation and the estimate all live in the core.
struct BrowserDownloadTransferEstimator {
    // MARK: - Variables

    private var state: BrowserCoreOpaqueValue?

    // MARK: - Actions - Sampling

    /// Nil when the core cannot answer; the caller keeps the last reading.
    mutating func sample(
        completedUnitCount: Int64,
        totalUnitCount: Int64,
        fractionCompleted: Double,
        isPaused: Bool,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> BrowserDownloadTransferUpdate? {
        guard
            let reading = BrowserCorePolicy.downloadProgress(
                estimator: state,
                completedUnitCount: completedUnitCount, totalUnitCount: totalUnitCount,
                fractionCompleted: fractionCompleted, isPaused: isPaused, uptime: uptime)
        else { return nil }
        state = reading.estimator
        return reading.update
    }
}
