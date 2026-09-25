import Foundation

/// Durable presentation chosen for a split group.
///
/// Membership remains on tabs because it participates in tab ordering. The
/// user-authored identity belongs to the stable `SplitGroupID` instead: a
/// head/member can move within the run without moving the group's name, icon,
/// or tint with a derived row. Per-field timestamps let sync merge a rename
/// and a color change made on different devices without treating either as a
/// rewrite of the other.
struct BrowserSplitGroupMetadata: Equatable, Identifiable, Sendable {
    static let defaultTitle = "Split View"

    let id: SplitGroupID
    var customTitle: String?
    var titleModifiedAt: Date?
    var customIconSymbol: String?
    var iconModifiedAt: Date?
    var tint: BrowserSpaceBrandColor?
    var tintModifiedAt: Date?

    init(
        id: SplitGroupID,
        customTitle: String? = nil,
        titleModifiedAt: Date? = nil,
        customIconSymbol: String? = nil,
        iconModifiedAt: Date? = nil,
        tint: BrowserSpaceBrandColor? = nil,
        tintModifiedAt: Date? = nil
    ) {
        self.id = id
        self.customTitle = BrowserTab.resolvedCustomTitle(customTitle)
        self.titleModifiedAt = titleModifiedAt.map(Self.normalizedTimestamp)
        self.customIconSymbol = Self.resolvedIcon(customIconSymbol)
        self.iconModifiedAt = iconModifiedAt.map(Self.normalizedTimestamp)
        self.tint = tint
        self.tintModifiedAt = tintModifiedAt.map(Self.normalizedTimestamp)
    }

    /// TRANSITIONAL until S6.6c1 moves the split row onto the read model's
    /// `SplitGroupState.displayTitle`, `defaultTitle` and `displayEmojiIcon`,
    /// which the core resolves; this and `emojiIcon` serve the views that read
    /// the session copy until then.
    var displayTitle: String {
        BrowserTab.resolvedCustomTitle(customTitle) ?? Self.defaultTitle
    }

    var emojiIcon: String? {
        customIconSymbol.flatMap(BrowserIconSymbol.emoji(from:))
    }

    mutating func setTitle(_ title: String?, at date: Date) {
        customTitle = BrowserTab.resolvedCustomTitle(title)
        titleModifiedAt = Self.normalizedTimestamp(date)
    }

    mutating func setEmojiIcon(_ emoji: String?, at date: Date) {
        customIconSymbol =
            emoji
            .flatMap(BrowserIconSymbol.normalizedEmoji)
            .map(BrowserIconSymbol.symbol(forEmoji:))
        iconModifiedAt = Self.normalizedTimestamp(date)
    }

    mutating func setTint(_ tint: BrowserSpaceBrandColor?, at date: Date) {
        self.tint = tint
        tintModifiedAt = Self.normalizedTimestamp(date)
    }

    static func normalized(_ source: [Self]) -> [Self] {
        var result: [Self] = []
        var indices: [SplitGroupID: Int] = [:]
        for metadata in source {
            let candidate = Self(
                id: metadata.id,
                customTitle: metadata.customTitle,
                titleModifiedAt: metadata.titleModifiedAt,
                customIconSymbol: metadata.customIconSymbol,
                iconModifiedAt: metadata.iconModifiedAt,
                tint: metadata.tint,
                tintModifiedAt: metadata.tintModifiedAt
            )
            if let index = indices[candidate.id] {
                result[index] = merged(
                    preferred: candidate,
                    fallback: result[index]
                )
            } else {
                indices[candidate.id] = result.endIndex
                result.append(candidate)
            }
        }
        return result
    }

    static func merged(preferred: Self, fallback: Self) -> Self {
        precondition(preferred.id == fallback.id)
        var result = preferred
        let titleSource = laterField(
            preferred: preferred,
            fallback: fallback,
            timestamp: \.titleModifiedAt
        )
        result.customTitle = titleSource.customTitle
        result.titleModifiedAt = titleSource.titleModifiedAt
        let iconSource = laterField(
            preferred: preferred,
            fallback: fallback,
            timestamp: \.iconModifiedAt
        )
        result.customIconSymbol = iconSource.customIconSymbol
        result.iconModifiedAt = iconSource.iconModifiedAt
        let tintSource = laterField(
            preferred: preferred,
            fallback: fallback,
            timestamp: \.tintModifiedAt
        )
        result.tint = tintSource.tint
        result.tintModifiedAt = tintSource.tintModifiedAt
        return result
    }

    private static func laterField(
        preferred: Self,
        fallback: Self,
        timestamp: KeyPath<Self, Date?>
    ) -> Self {
        switch (preferred[keyPath: timestamp], fallback[keyPath: timestamp]) {
        case (let preferredDate?, let fallbackDate?) where fallbackDate > preferredDate:
            fallback
        case (nil, _?):
            fallback
        default:
            preferred
        }
    }

    private static func resolvedIcon(_ symbol: String?) -> String? {
        guard let symbol,
            let emoji = BrowserIconSymbol.emoji(from: symbol)
        else { return nil }
        return BrowserIconSymbol.symbol(forEmoji: emoji)
    }

    private static func normalizedTimestamp(_ date: Date) -> Date {
        let milliseconds = (date.timeIntervalSince1970 * 1_000).rounded()
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }
}

// MARK: - Codable

extension BrowserSplitGroupMetadata: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case customTitle
        case titleModifiedAt
        case customIconSymbol
        case iconModifiedAt
        case tint
        case tintModifiedAt
    }

    /// Reads the stored values as they are; only `init(id:…)` resolves them.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIdentity(forKey: .id)
        customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        titleModifiedAt = try container.decodeIfPresent(Date.self, forKey: .titleModifiedAt)
        customIconSymbol = try container.decodeIfPresent(String.self, forKey: .customIconSymbol)
        iconModifiedAt = try container.decodeIfPresent(Date.self, forKey: .iconModifiedAt)
        tint = try container.decodeIfPresent(BrowserSpaceBrandColor.self, forKey: .tint)
        tintModifiedAt = try container.decodeIfPresent(Date.self, forKey: .tintModifiedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeStoredIdentity(id, forKey: .id)
        try container.encodeIfPresent(customTitle, forKey: .customTitle)
        try container.encodeIfPresent(titleModifiedAt, forKey: .titleModifiedAt)
        try container.encodeIfPresent(customIconSymbol, forKey: .customIconSymbol)
        try container.encodeIfPresent(iconModifiedAt, forKey: .iconModifiedAt)
        try container.encodeIfPresent(tint, forKey: .tint)
        try container.encodeIfPresent(tintModifiedAt, forKey: .tintModifiedAt)
    }
}
