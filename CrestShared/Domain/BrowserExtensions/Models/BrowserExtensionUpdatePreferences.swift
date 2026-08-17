import Foundation

/// Whether and how often Crest updates store-sourced extensions.
///
/// These preferences are global rather than per Space. The installations they
/// govern stay strictly Space-scoped — an update replaces each Space's own
/// package independently — but the *cadence* is a single browser-wide
/// housekeeping setting, and a per-Space cadence would multiply identical
/// store requests by the number of Spaces that installed the same extension.
struct BrowserExtensionUpdatePreferences: Codable, Equatable, Sendable {
    static let `default` = BrowserExtensionUpdatePreferences(
        isAutomaticUpdateEnabled: true,
        updateFrequency: .weekly
    )

    var isAutomaticUpdateEnabled: Bool
    var updateFrequency: BrowserExtensionUpdateFrequency

    init(
        isAutomaticUpdateEnabled: Bool = true,
        updateFrequency: BrowserExtensionUpdateFrequency = .weekly
    ) {
        self.isAutomaticUpdateEnabled = isAutomaticUpdateEnabled
        self.updateFrequency = updateFrequency
    }

    /// Tolerates a payload written by a build that did not have every field
    /// yet, so an older or partially written record degrades to the default
    /// cadence instead of resetting the whole preference.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isAutomaticUpdateEnabled =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .isAutomaticUpdateEnabled
            ) ?? Self.default.isAutomaticUpdateEnabled
        updateFrequency =
            try container.decodeIfPresent(
                BrowserExtensionUpdateFrequency.self,
                forKey: .updateFrequency
            ) ?? Self.default.updateFrequency
    }

    private enum CodingKeys: String, CodingKey {
        case isAutomaticUpdateEnabled
        case updateFrequency
    }
}

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
