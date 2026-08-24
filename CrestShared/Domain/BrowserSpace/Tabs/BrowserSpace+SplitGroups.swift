import Foundation

extension BrowserSpace {
    func splitGroupMetadata(
        for groupID: SplitGroupID
    ) -> BrowserSplitGroupMetadata? {
        splitGroups.first { $0.id == groupID }
    }

    /// The renderable split group this tab belongs to, or `nil`.
    ///
    /// A run shorter than `BrowserSplitGroupPolicy.minimumRenderableMembers`
    /// answers `nil` on purpose: storage keeps a lone member's ID so a
    /// staggered sync can reconstitute the group, while every presentation
    /// surface treats that member as a plain tab until its siblings arrive.
    func splitGroup(containing tabID: TabID) -> SplitGroupID? {
        guard let groupID = tabs.first(where: { $0.id == tabID })?.splitGroupID else {
            return nil
        }
        let members = splitGroupMembers(of: groupID)
        guard members.count >= BrowserSplitGroupPolicy.minimumRenderableMembers,
            members.contains(where: { $0.id == tabID })
        else { return nil }
        return groupID
    }

    /// The group's members in session-array order: the first maximal
    /// contiguous run of tabs carrying `groupID`.
    func splitGroupMembers(of groupID: SplitGroupID) -> [BrowserTab] {
        guard let start = tabs.firstIndex(where: { $0.splitGroupID == groupID }) else {
            return []
        }
        var end = start
        while end < tabs.endIndex, tabs[end].splitGroupID == groupID {
            end += 1
        }
        return Array(tabs[start..<end])
    }

    /// The cards the content area presents for this selection: the selected
    /// tab's renderable run, otherwise just the selected tab, otherwise
    /// nothing. The single-tab case is deliberately the same shape as a group
    /// so no surface has to special-case it.
    func presentedSplitMembers(for selectedTabID: TabID?) -> [BrowserTab] {
        guard let selectedTabID,
            let selectedTab = tabs.first(where: { $0.id == selectedTabID })
        else { return [] }
        guard let groupID = splitGroup(containing: selectedTabID) else {
            return [selectedTab]
        }
        return splitGroupMembers(of: groupID)
    }

    /// Every group ID whose first contiguous run is long enough to render.
    /// Device-local stores keyed by `SplitGroupID` repair themselves against
    /// this set.
    var liveSplitGroupIDs: Set<SplitGroupID> {
        var live: Set<SplitGroupID> = []
        var startedIDs: Set<SplitGroupID> = []
        var runID: SplitGroupID?
        var runLength = 0

        for tab in tabs {
            guard let groupID = tab.splitGroupID else {
                runID = nil
                runLength = 0
                continue
            }
            if groupID == runID {
                runLength += 1
            } else if startedIDs.insert(groupID).inserted {
                runID = groupID
                runLength = 1
            } else {
                // A later re-occurrence is not this group's run.
                runID = nil
                runLength = 0
                continue
            }
            if runLength >= BrowserSplitGroupPolicy.minimumRenderableMembers {
                live.insert(groupID)
            }
        }
        return live
    }
}

/// Durable presentation chosen for a split group.
///
/// Membership remains on tabs because it participates in tab ordering. The
/// user-authored identity belongs to the stable `SplitGroupID` instead: a
/// head/member can move within the run without moving the group's name, icon,
/// or tint with a derived row. Per-field timestamps let sync merge a rename
/// and a color change made on different devices without treating either as a
/// rewrite of the other.
struct BrowserSplitGroupMetadata: Codable, Equatable, Identifiable, Sendable {
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
