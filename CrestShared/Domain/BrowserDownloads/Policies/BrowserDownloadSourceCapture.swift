import Foundation

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
            BrowserCorePolicy.acceptsExternalURL(destinationURL),
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
