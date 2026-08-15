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
