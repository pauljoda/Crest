import Foundation

enum BrowserDownloadProgressPolicy {
    static let minimumPublishedDelta = 0.01

    static func normalized(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }

    static func shouldPublish(previous: Double, next: Double) -> Bool {
        let previous = normalized(previous)
        let next = normalized(next)
        return next == 0
            || next == 1
            || abs(next - previous) >= minimumPublishedDelta
    }
}

struct BrowserDownloadTransferUpdate: Equatable, Sendable {
    let telemetry: BrowserDownloadTransferTelemetry
    let progress: Double
}

/// Turns event-driven `Progress` samples into stable row telemetry.
///
/// Samples are accumulated until enough wall time has elapsed for a useful
/// rate, then smoothed with an exponential moving average. Reported byte counts
/// never move backwards. A Content-Length that is disproved by received bytes
/// is discarded instead of producing a downloaded count larger than its total.
struct BrowserDownloadTransferEstimator: Equatable, Sendable {
    private static let minimumRateInterval: TimeInterval = 0.15
    private static let smoothingWeight = 0.25
    private static let maximumUsefulETA: TimeInterval = 7 * 24 * 60 * 60

    private var publishedBytes: Int64 = 0
    private var knownTotalBytes: Int64?
    private var totalIsUnreliable = false
    private var measurementBytes: Int64?
    private var measurementUptime: TimeInterval?
    private var smoothedBytesPerSecond: Double?

    mutating func sample(
        completedUnitCount: Int64,
        totalUnitCount: Int64,
        fractionCompleted: Double,
        isPaused: Bool,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> BrowserDownloadTransferUpdate {
        let reportedBytes = max(completedUnitCount, 0)
        publishedBytes = max(publishedBytes, reportedBytes)
        updateKnownTotal(reportedTotal: totalUnitCount)

        if isPaused {
            measurementBytes = publishedBytes
            measurementUptime = uptime
            smoothedBytesPerSecond = nil
        } else {
            updateRate(uptime: uptime)
        }

        let progress: Double
        if let knownTotalBytes, knownTotalBytes > 0 {
            progress = BrowserDownloadProgressPolicy.normalized(
                Double(publishedBytes) / Double(knownTotalBytes)
            )
        } else {
            progress = BrowserDownloadProgressPolicy.normalized(fractionCompleted)
        }

        let rate = isPaused ? nil : smoothedBytesPerSecond
        return BrowserDownloadTransferUpdate(
            telemetry: BrowserDownloadTransferTelemetry(
                bytesReceived: publishedBytes,
                totalBytes: knownTotalBytes,
                bytesPerSecond: rate,
                estimatedTimeRemaining: estimatedTimeRemaining(rate: rate),
                isPaused: isPaused
            ),
            progress: progress
        )
    }

    private mutating func updateKnownTotal(reportedTotal: Int64) {
        guard !totalIsUnreliable else { return }
        guard reportedTotal > 0 else { return }
        guard reportedTotal >= publishedBytes else {
            knownTotalBytes = nil
            totalIsUnreliable = true
            return
        }
        knownTotalBytes = max(knownTotalBytes ?? 0, reportedTotal)
    }

    private mutating func updateRate(uptime: TimeInterval) {
        guard let measurementBytes, let measurementUptime else {
            self.measurementBytes = publishedBytes
            self.measurementUptime = uptime
            return
        }
        let elapsed = uptime - measurementUptime
        guard elapsed.isFinite, elapsed >= Self.minimumRateInterval else { return }
        let transferred = publishedBytes - measurementBytes
        self.measurementBytes = publishedBytes
        self.measurementUptime = uptime
        guard transferred > 0 else { return }

        let instantaneousRate = Double(transferred) / elapsed
        guard instantaneousRate.isFinite, instantaneousRate > 0 else { return }
        if let smoothedBytesPerSecond {
            self.smoothedBytesPerSecond =
                smoothedBytesPerSecond * (1 - Self.smoothingWeight)
                + instantaneousRate * Self.smoothingWeight
        } else {
            smoothedBytesPerSecond = instantaneousRate
        }
    }

    private func estimatedTimeRemaining(rate: Double?) -> TimeInterval? {
        guard let knownTotalBytes,
            let rate,
            rate.isFinite,
            rate > 0
        else { return nil }
        let remainingBytes = max(knownTotalBytes - publishedBytes, 0)
        guard remainingBytes > 0 else { return nil }
        let estimate = Double(remainingBytes) / rate
        guard estimate.isFinite,
            estimate >= 0.5,
            estimate <= Self.maximumUsefulETA
        else { return nil }
        return estimate
    }
}

/// A trusted primary-pointer activation reported from Crest's private WebKit
/// content world. Only geometry and the already-owned download destination are
/// retained, and only long enough to match the ensuing download callback.
struct BrowserDownloadSourceCapture: Equatable, Sendable {
    let destinationURL: URL
    let normalizedSourceRect: CGRect
    let normalizedTouchPoint: CGPoint

    init(
        destinationURL: URL,
        normalizedSourceRect: CGRect,
        normalizedTouchPoint: CGPoint
    ) {
        self.destinationURL = destinationURL
        let minX = Self.normalized(normalizedSourceRect.minX)
        let minY = Self.normalized(normalizedSourceRect.minY)
        let width = min(Self.normalized(normalizedSourceRect.width), 1 - minX)
        let height = min(Self.normalized(normalizedSourceRect.height), 1 - minY)
        self.normalizedSourceRect = CGRect(
            x: minX,
            y: minY,
            width: width,
            height: height
        )
        self.normalizedTouchPoint = CGPoint(
            x: Self.normalized(normalizedTouchPoint.x),
            y: Self.normalized(normalizedTouchPoint.y)
        )
    }

    init?(messageBody: Any) {
        guard let values = messageBody as? [String: Any],
            Self.integer(values["version"]) == 1,
            values["kind"] as? String == "activation",
            let href = values["href"] as? String,
            href.count <= 4_096,
            let destinationURL = URL(string: href),
            BrowserExternalURLPolicy.accepts(destinationURL),
            let minX = Self.number(values["minX"]),
            let minY = Self.number(values["minY"]),
            let width = Self.number(values["width"]),
            let height = Self.number(values["height"]),
            let touchX = Self.number(values["touchX"]),
            let touchY = Self.number(values["touchY"])
        else { return nil }

        self.init(
            destinationURL: destinationURL,
            normalizedSourceRect: CGRect(
                x: minX,
                y: minY,
                width: width,
                height: height
            ),
            normalizedTouchPoint: CGPoint(x: touchX, y: touchY)
        )
    }

    private static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        return value as? Double
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        return value as? Int
    }
}

struct BrowserDownloadSourceStore: Equatable, Sendable {
    private struct Entry: Equatable, Sendable {
        let capture: BrowserDownloadSourceCapture
        let uptime: TimeInterval
    }

    private static let maximumEntries = 8

    let maximumAge: TimeInterval
    private var entries: [Entry] = []

    init(maximumAge: TimeInterval = 8) {
        precondition(maximumAge > 0)
        self.maximumAge = maximumAge
    }

    mutating func record(
        _ capture: BrowserDownloadSourceCapture,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        removeExpired(uptime: uptime)
        entries.append(Entry(capture: capture, uptime: uptime))
        entries = Array(entries.suffix(Self.maximumEntries))
    }

    mutating func consume(
        destinationURL: URL?,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> BrowserDownloadSourceCapture? {
        removeExpired(uptime: uptime)
        guard let destination = destinationURL?.absoluteString,
            let index = entries.firstIndex(where: {
                $0.capture.destinationURL.absoluteString == destination
            })
        else { return nil }
        return entries.remove(at: index).capture
    }

    mutating func removeAll() {
        entries.removeAll()
    }

    private mutating func removeExpired(uptime: TimeInterval) {
        entries.removeAll { entry in
            let age = uptime - entry.uptime
            return age < 0 || age > maximumAge
        }
    }
}

struct BrowserDownloadFeedbackSource: Equatable, @unchecked Sendable {
    let pointInGlobal: CGPoint
    let windowIdentifier: ObjectIdentifier?
}

struct BrowserDownloadFeedbackEvent: Identifiable, Equatable, @unchecked Sendable {
    let id: UUID
    let profileID: UUID
    let spaceID: SpaceID
    let filename: String
    let source: BrowserDownloadFeedbackSource
}

enum BrowserDownloadFeedbackPresentation: Equatable, Sendable {
    case flight
    case destinationFade
    case none
}

enum BrowserDownloadFeedbackPolicy {
    static let maximumVisibleEvents = 3
    static let lifetime: Duration = .milliseconds(1_400)

    static func presentation(
        hasSource: Bool,
        hasSidebarDestination: Bool,
        reduceMotion: Bool
    ) -> BrowserDownloadFeedbackPresentation {
        guard hasSource, hasSidebarDestination else { return .none }
        return reduceMotion ? .destinationFade : .flight
    }

    static func bounded(
        _ events: [BrowserDownloadFeedbackEvent],
        appending event: BrowserDownloadFeedbackEvent
    ) -> [BrowserDownloadFeedbackEvent] {
        Array((events + [event]).suffix(maximumVisibleEvents))
    }
}

enum BrowserDownloadInitiationPolicy {
    /// Only Crest's trusted activation bridge may strengthen WebKit's own
    /// initiation signal. A synthetic `.linkActivated` navigation is not proof
    /// of a user gesture and must remain subject to automatic-download policy.
    static func userInitiatedOverride(
        hasTrustedSource: Bool
    ) -> Bool? {
        hasTrustedSource ? true : nil
    }
}
