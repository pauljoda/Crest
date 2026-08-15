import Foundation

/// How often Crest re-checks the Chrome Web Store for newer packages.
///
/// There is deliberately no `manual` case here, unlike the filter-list
/// cadence. Automatic updating is its own switch, and **Check for Updates
/// Now** stays available whether or not the schedule is running, so a
/// "manual" frequency would only be a second way to spell "off".
enum BrowserExtensionUpdateFrequency:
    String,
    Codable,
    CaseIterable,
    Identifiable,
    Sendable
{
    case daily
    case weekly
    case biweekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: String(localized: "Daily")
        case .weekly: String(localized: "Weekly")
        case .biweekly: String(localized: "Every Two Weeks")
        }
    }

    /// Whether a pass is owed as of `now`.
    ///
    /// A profile that has never checked is always due, so a first launch
    /// after enabling the toggle reaches the store instead of waiting out a
    /// full interval against a timestamp that does not exist yet.
    func isDue(lastCheckedAt: Date?, now: Date = .now) -> Bool {
        guard let lastCheckedAt else { return true }
        return now.timeIntervalSince(lastCheckedAt) >= interval
    }

    /// How long to wait before the next pass, never negative.
    func timeUntilDue(lastCheckedAt: Date?, now: Date = .now) -> TimeInterval {
        guard let lastCheckedAt else { return 0 }
        return max(0, interval - now.timeIntervalSince(lastCheckedAt))
    }

    private var interval: TimeInterval {
        switch self {
        case .daily: 24 * 60 * 60
        case .weekly: 7 * 24 * 60 * 60
        case .biweekly: 14 * 24 * 60 * 60
        }
    }
}
